import Foundation
import Security

private enum CertLoadError: Error { case notFound(String), badData(String) }

private func loadBundleCert(named base: String) throws -> SecCertificate {
	// Try common extensions in order
	let exts = ["cer", "pem", "crt", "der"]
	var lastErr: Error?

	for ext in exts {
		if let url = Bundle.sharedAppBundle.url(forResource: base, withExtension: ext) {
			do {
				let data = try Data(contentsOf: url)
				let der = try normalizeToDER(data: data)
				if let cert = SecCertificateCreateWithData(nil, der as CFData) {
					return cert
				} else {
					throw CertLoadError.badData("\(base).\(ext) not a valid X.509")
				}
			} catch {
				lastErr = error
				continue
			}
		}
	}
	throw lastErr ?? CertLoadError.notFound("Could not find \(base).{cer|pem|crt|der} in bundle")
}

/// If data is PEM, decode to DER; if already DER, return as-is.
private func normalizeToDER(data: Data) throws -> Data {
	if let s = String(data: data, encoding: .utf8),
	   s.contains("-----BEGIN CERTIFICATE-----") {
		// PEM → DER
		let lines = s
			.replacingOccurrences(of: "\r", with: "")
			.components(separatedBy: "\n")
			.filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") && !$0.isEmpty }
		guard let der = Data(base64Encoded: lines.joined()) else {
			throw CertLoadError.badData("PEM base64 decode failed")
		}
		return der
	} else {
		// Assume DER already
		return data
	}
}

public final class RemoteAccessAPI: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
	private let baseURL: URL
	private var urlSession: URLSession!
	private let pinnedRoot: SecCertificate?
	private let skipHostValidation: Bool
	private let acceptAnyCertificate: Bool
	public var accessToken: String?

	public init(
		baseURL: URL,
		pinnedRootDer: Data? = nil,
		skipHostValidation: Bool = false,
		acceptAnyCertificate: Bool = false
	) {
		self.baseURL = baseURL
		if let der = pinnedRootDer, let cert = SecCertificateCreateWithData(nil, der as CFData) {
			self.pinnedRoot = cert
		} else {
			self.pinnedRoot = try? loadBundleCert(named: "fake-device-noveo")
		}
		self.skipHostValidation = skipHostValidation
		self.acceptAnyCertificate = acceptAnyCertificate
		super.init()

		let cfg = URLSessionConfiguration.default
		cfg.timeoutIntervalForRequest = 15
		cfg.timeoutIntervalForResource = 30
		self.urlSession = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
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
		let (data, resp) = try await urlSession.data(for: req)
		try ensureOK(resp)
		return try JSONDecoder().decode(RAInitiateResponse.self, from: data)
	}

	public func validateEmailCode(code: String, reference: String) async throws -> RATokenResponse {
		var comps = URLComponents(url: baseURL.appendingPathComponent("client/v1/auth/token"), resolvingAgainstBaseURL: false)!
		comps.queryItems = [URLQueryItem(name: "type", value: "email")]
		var req = URLRequest(url: comps.url!)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField: "Content-Type")
		let body: [String: Any] = [
			"code": code,
			"reference": reference
		]
		req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
		let (data, resp) = try await urlSession.data(for: req)
		try ensureOK(resp)
		return try JSONDecoder().decode(RATokenResponse.self, from: data)
	}

	public func refreshAccessToken(refreshToken: String) async throws -> RATokenResponse {
		var comps = URLComponents(url: baseURL.appendingPathComponent("client/v1/auth/refresh"), resolvingAgainstBaseURL: false)!
		comps.queryItems = [URLQueryItem(name: "refresh_token", value: refreshToken)]
		var req = URLRequest(url: comps.url!)
		req.httpMethod = "GET"
		let (data, resp) = try await urlSession.data(for: req)
		try ensureOK(resp)
		return try JSONDecoder().decode(RATokenResponse.self, from: data)
	}

	public func listDevices() async throws -> [RADevice] {
		var req = URLRequest(url: baseURL.appendingPathComponent("client/v1/devices"))
		req.httpMethod = "GET"
		injectAuth(&req)
		let (data, resp) = try await urlSession.data(for: req)
		try ensureOK(resp)
		return try JSONDecoder().decode([RADevice].self, from: data)
	}

	public func getDevicePaths(deviceID: String) async throws -> RADevicePaths {
		var req = URLRequest(url: baseURL.appendingPathComponent("client/v1/devices/\(deviceID)"))
		req.httpMethod = "GET"
		injectAuth(&req)
		let (data, resp) = try await urlSession.data(for: req)
		try ensureOK(resp)
		return try JSONDecoder().decode(RADevicePaths.self, from: data)
	}

	private func ensureOK(_ response: URLResponse) throws {
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			let code = (response as? HTTPURLResponse)?.statusCode ?? -1
			throw NSError(domain: "RemoteAccessAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
		}
	}

	private func injectAuth(_ request: inout URLRequest) {
		guard let token = accessToken else { return }
		if request.value(forHTTPHeaderField: "Authorization") == nil {
			request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		}
	}

	private func handleServerTrust(
		_ challenge: URLAuthenticationChallenge,
		anchorCA: SecCertificate,
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
		SecTrustSetAnchorCertificates(trust, [anchorCA] as CFArray)
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
            if HCConfig.disableCertificatePinning || acceptAnyCertificate {
                if let trust = challenge.protectionSpace.serverTrust {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
                return
            }
			guard let pinnedRoot else {
				completionHandler(.performDefaultHandling, nil)
				return
			}

			handleServerTrust(challenge, anchorCA: pinnedRoot, completionHandler)
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
            if HCConfig.disableCertificatePinning || acceptAnyCertificate {
                if let trust = challenge.protectionSpace.serverTrust {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
                return
            }
			guard let pinnedRoot else {
				completionHandler(.performDefaultHandling, nil)
				return
			}

			handleServerTrust(challenge, anchorCA: pinnedRoot, completionHandler)
        } else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
			handleClientCert(challenge, completionHandler)
		} else {
			completionHandler(.performDefaultHandling, nil)
		}
	}

	// Log redirects clearly (host changes => new challenge)
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

	// Add this helper to see what auth methods you’re getting.
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
