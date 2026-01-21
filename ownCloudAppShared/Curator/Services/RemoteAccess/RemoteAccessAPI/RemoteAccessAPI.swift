import Foundation
import Security

public enum RemoteAccessAPIError: Error, Sendable {
	case unauthorized(Unauthorized) // HTTP 401
	case tooManyRequests(RAError?) // HTTP 429
	case forbidden(RAError?) // HTTP 403
	case internalServerError(RAError?) // 500
	case httpStatus(code: Int, body: Data?) // HTTP other

	case cancelled
	case transport(URLError)
	case decoding(DecodingError)
	case unexpected(AnySendableError)

	public struct Unauthorized: Error, Sendable {
		public let kind: Kind

		public enum Kind: Sendable, Decodable {
			case codeExpired
			case codeInvalid
			case emailNotRegistered
			case unknown(name: String?, stacktrace: String?)

			static func decode(from data: Data, decoder: JSONDecoder) -> Self {
				if let raError = try? decoder.decode(RAError.self, from: data) {
					let name = raError.name ?? ""
					let stacktrace = raError.stacktrace ?? ""
					switch raError.name {
						case "invalid credentials":
							return .codeInvalid
						case "verification code expired":
							return .codeExpired
						case "not allowed":
							return .emailNotRegistered
						default:
							return .unknown(name: name, stacktrace: stacktrace)
					}
				}
				return .unknown(name: nil, stacktrace: nil)
			}
		}
	}

	init(catching error: any Error) {
		if error is CancellationError {
			self = .cancelled
			return
		}

		switch error {
			case let e as RemoteAccessAPIError:
				self = e
			case let e as URLError:
				self = .transport(e)
			case let e as DecodingError:
				self = .decoding(e)
			default:
				self = .unexpected(.init(error))
		}
	}
}

public final class RemoteAccessAPI: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
	private let baseURL: URL
	private var urlSession: URLSession!
	private let decoder = JSONDecoder()
	private var pinnedRoots: [SecCertificate] = []
	private let skipHostValidation: Bool
	public var accessToken: String?

	public init(
		baseURL: URL,
		skipHostValidation: Bool = false,
	) {
		self.baseURL = baseURL
		self.skipHostValidation = skipHostValidation
		super.init()

		self.pinnedRoots = loadRAPins()

		let cfg = URLSessionConfiguration.default
		cfg.timeoutIntervalForRequest = 15
		cfg.timeoutIntervalForResource = 30
		self.urlSession = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
	}

	public func request<T: Decodable>(_ urlRequest: URLRequest) async throws -> T {
		do {
			let (data, response) = try await urlSession.data(for: urlRequest)
			let http = try requireHTTP(response)

			if (200..<300).contains(http.statusCode) {
				do {
					return try decoder.decode(T.self, from: data)
				} catch let error as DecodingError {
					throw RemoteAccessAPIError.decoding(error)
				}
			}

			throw mapHTTPError(status: http.statusCode, body: data, headers: http.allHeaderFields)
		}
	}

	private func loadBundleCert(named base: String) -> SecCertificate? {
		guard let url = Bundle.sharedAppBundle.url(forResource: base, withExtension: nil) else {
			return nil
		}
		do {
			let data = try Data(contentsOf: url)
			let der = try data.normalizeToDER()
			if let cert = SecCertificateCreateWithData(nil, der as CFData) {
				return cert
			} else {
				return nil
			}
		} catch {
			return nil
		}
	}

	private func loadRAPins() -> [SecCertificate] {
		HCConfig.raPinnedCertificateFiles.compactMap {
			loadBundleCert(named: $0)
		}
	}

	private func requireHTTP(_ response: URLResponse) throws -> HTTPURLResponse {
		guard let http = response as? HTTPURLResponse else {
			throw RemoteAccessAPIError.unexpected(.init(NSError(domain: "NonHTTPResponse", code: 0)))
		}
		return http
	}

	private func mapHTTPError(status: Int, body: Data, headers: [AnyHashable: Any]) -> RemoteAccessAPIError {
		switch status {
			case 401:
				let kind = RemoteAccessAPIError.Unauthorized.Kind.decode(from: body, decoder: decoder)
				return .unauthorized(.init(kind: kind))

			case 403:
				let raError = try? decoder.decode(RAError.self, from: body)
				return .forbidden(raError)

			case 429:
				let raError = try? decoder.decode(RAError.self, from: body)
				return .tooManyRequests(raError)

			case 500:
				let raError = try? decoder.decode(RAError.self, from: body)
				return .internalServerError(raError)

			default:
				return .httpStatus(code: status, body: body)
		}
	}

	public func sendEmailCode(
		email: String,
		clientId: String,
		clientFriendlyName: String
	) async throws -> RAInitiateResponse {
		var comps = URLComponents(url: baseURL.appendingPathComponent("client/v1/auth/initiate"), resolvingAgainstBaseURL: false)!
		comps.queryItems = [URLQueryItem(name: "type", value: "email")]
		var req = URLRequest(url: comps.url!)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		let body: [String: Any] = [
			"email": email,
			"clientId": clientId,
			"clientFriendlyName": clientFriendlyName
		]
		req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

		return try await request(req)
	}

	public func validateEmailCode(
		code: String,
		clientId: String,
		reference: String
	) async throws -> RATokenResponse {
		var comps = URLComponents(url: baseURL.appendingPathComponent("client/v1/auth/token"), resolvingAgainstBaseURL: false)!
		comps.queryItems = [URLQueryItem(name: "type", value: "email")]
		var req = URLRequest(url: comps.url!)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		let body: [String: Any] = [
			"code": code,
			"reference": reference,
			"clientId": clientId
		]
		req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

		return try await request(req)
	}

	public func refreshAccessToken(
		clientId: String,
		refreshToken: String
	) async throws -> RATokenResponse {
		var req = URLRequest(url: baseURL.appendingPathComponent("client/v1/auth/refresh"))
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		let body: [String: Any] = [
			"refreshToken": refreshToken,
			"clientId": clientId
		]
		req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

		return try await request(req)
	}

	public func listDevices() async throws -> [RADevice] {
		var req = URLRequest(url: baseURL.appendingPathComponent("client/v1/devices"))
		req.httpMethod = "GET"
		injectAuth(&req)

		return try await request(req)
	}

	public func getDevicePaths(deviceID: String) async throws -> RADevicePaths {
		var req = URLRequest(url: baseURL.appendingPathComponent("client/v1/devices/\(deviceID)"))
		req.httpMethod = "GET"
		injectAuth(&req)

		return  try await request(req)
	}

	private func injectAuth(_ request: inout URLRequest) {
		guard let token = accessToken else { return }
		if request.value(forHTTPHeaderField: "Authorization") == nil {
			request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		}
	}
}

extension RemoteAccessAPI {
	private func handleServerTrust(
		_ challenge: URLAuthenticationChallenge,
		anchors: [SecCertificate],
		_ completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		guard
			challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
			let trust = challenge.protectionSpace.serverTrust
		else {
			completion(.performDefaultHandling, nil)
			return
		}

		SecTrustSetPolicies(trust, SecPolicyCreateSSL(false, nil))
		SecTrustSetAnchorCertificates(trust, anchors as CFArray)
		SecTrustSetAnchorCertificatesOnly(trust, true)
		SecTrustSetNetworkFetchAllowed(trust, false)

		var err: CFError?
		if SecTrustEvaluateWithError(trust, &err) {
			completion(.useCredential, URLCredential(trust: trust))
		} else {
			completion(.cancelAuthenticationChallenge, nil)
		}
	}

	private func handleClientCert(
		_ challenge: URLAuthenticationChallenge,
		_ completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		Log.debug("[STX-RA]: Client certificate requested but none provided.")
		completion(.cancelAuthenticationChallenge, nil)
	}

	public func urlSession(
		_ session: URLSession,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		let m = describeAuthMethod(challenge.protectionSpace.authenticationMethod)
		Log.debug("[STX-RA]: Session challenge: \(m) host: \(challenge.protectionSpace.host)")

		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
			if HCConfig.disableCertificatePinning {
				if let trust = challenge.protectionSpace.serverTrust {
					completionHandler(.useCredential, URLCredential(trust: trust))
				} else {
					completionHandler(.performDefaultHandling, nil)
				}
				return
			}
			guard pinnedRoots.isEmpty == false else {
				completionHandler(.performDefaultHandling, nil)
				return
			}

			handleServerTrust(challenge, anchors: pinnedRoots, completionHandler)
		} else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
			handleClientCert(challenge, completionHandler)
		} else {
			completionHandler(.performDefaultHandling, nil)
		}
	}

	public func urlSession(
		_ session: URLSession, task: URLSessionTask,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		let m = describeAuthMethod(challenge.protectionSpace.authenticationMethod)
		Log.debug("[STX-RA]: Task challenge: \(m) host: \(challenge.protectionSpace.host)")

		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
			if HCConfig.disableCertificatePinning {
				if let trust = challenge.protectionSpace.serverTrust {
					completionHandler(.useCredential, URLCredential(trust: trust))
				} else {
					completionHandler(.performDefaultHandling, nil)
				}
				return
			}
			guard pinnedRoots.isEmpty == false else {
				completionHandler(.performDefaultHandling, nil)
				return
			}

			handleServerTrust(challenge, anchors: pinnedRoots, completionHandler)
		} else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
			handleClientCert(challenge, completionHandler)
		} else {
			completionHandler(.performDefaultHandling, nil)
		}
	}

	public func urlSession(
		_ session: URLSession, task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping (URLRequest?) -> Void
	) {
		Log.debug("[STX-RA]: Redirect: \(response.url?.host ?? "?") → \(request.url?.host ?? "?")")
		completionHandler(request)
	}

	public func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		didCompleteWithError error: Error?
	) {
		if let e = error as NSError? {
			Log.debug("[STX-RA]: Task complete error: \(e.domain) \(e.code) \(e.userInfo)")
		} else {
			Log.debug("[STX-RA]: Task complete OK")
			print("Task complete: ok")
		}
	}

	private func describeAuthMethod(_ m: String) -> String {
		switch m {
		case NSURLAuthenticationMethodServerTrust:       return "ServerTrust"
		case NSURLAuthenticationMethodClientCertificate: return "ClientCertificate"
		case NSURLAuthenticationMethodHTTPBasic:         return "HTTPBasic"
		case NSURLAuthenticationMethodHTTPDigest:        return "HTTPDigest"
		default:                                         return m
		}
	}
}
