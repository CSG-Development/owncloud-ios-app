import Foundation
import Security

public final class DeviceAPI: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let baseURL: URL
    private var session: URLSession!
    private let rootCertificate: SecCertificate?

    public init(baseURL: URL, rootCertDerData: Data? = nil) {
        self.baseURL = baseURL
        if let der = rootCertDerData, let cert = SecCertificateCreateWithData(nil, der as CFData) {
            self.rootCertificate = cert
        } else {
            self.rootCertificate = nil
        }
        super.init()

        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

	public func getStatus() async throws -> Status {
		var req = URLRequest(url: baseURL.appendingPathComponent("status"))
		req.httpMethod = "GET"
        let (data, response) = try await session.data(for: req, delegate: self)
		try Self.ensureOK(response)

		return try JSONDecoder().decode(Status.self, from: data)
	}

	public func getAbout() async throws -> About {
		var req = URLRequest(url: baseURL.appendingPathComponent("about"))
		req.httpMethod = "GET"
        let (data, response) = try await session.data(for: req, delegate: self)
		try Self.ensureOK(response)

		return try JSONDecoder().decode(About.self, from: data)
	}

	private static func ensureOK(_ response: URLResponse) throws {
		guard let http = response as? HTTPURLResponse else { return }
		guard (200..<300).contains(http.statusCode) else {
			if http.statusCode == 401 || http.statusCode == 403 {
				throw URLError(.userAuthenticationRequired)
			}
			throw NSError(domain: "DeviceAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
		}
	}
}
// MARK: - TLS Pinning / Delegate
extension DeviceAPI {
    public func urlSession(
		_ session: URLSession,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if HCConfig.disableCertificatePinning {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        guard let anchor = rootCertificate else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Basic X509 policy, no hostname enforcement
        let policy = SecPolicyCreateBasicX509()
        SecTrustSetPolicies(serverTrust, policy)
        SecTrustSetAnchorCertificates(serverTrust, [anchor] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)
        var evalError: CFError?
        if SecTrustEvaluateWithError(serverTrust, &evalError) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
