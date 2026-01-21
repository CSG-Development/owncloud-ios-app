import ownCloudSDK

private enum Constants {
	static let remoteAccessBaseURL = URL(
		string: "https://hc-remote-access-env-https.eba-a2nvhpbm.us-west-2.elasticbeanstalk.com:443/api"
	)!
}

public final class HCContext {
	public static let shared = HCContext()

	public let preferences: HCPreferences
	public let remoteAccessService: RemoteAccessService
	public let deviceReachabilityService: DeviceReachabilityService
	public let mdnsService: MDNSService
	public let remoteAccessTokenStore: RemoteAccessTokenStore
	public var emailVerificationHandler: (@MainActor (_ email: String, _ completion: @escaping (Bool) -> Void) -> Void)?

	// Hack to provide this info for related data sources.
	// Use `RemoteAccessSharingURLResolver` directly if possible.
	public var lastRemoteBaseURL: URL?

	public init() {
		self.preferences = HCPreferences()
		self.remoteAccessTokenStore = RemoteAccessTokenStore()

		self.remoteAccessService = RemoteAccessService(
			api: RemoteAccessAPI(baseURL: Constants.remoteAccessBaseURL),
			tokenStore: remoteAccessTokenStore
		)
		self.mdnsService = MDNSService()

		self.deviceReachabilityService = DeviceReachabilityService(
			reachability: DefaultReachabilityObserver(),
			remoteAccessService: remoteAccessService,
			mdnsService: mdnsService,
			preferences: preferences
		)

		Task {
			await self.deviceReachabilityService.observeRemoteBaseURL { url in
				self.lastRemoteBaseURL = url
			}
		}
	}

	public func setup() {
		Task { OCConnection.defaultBaseURLProvider = await deviceReachabilityService.urlProvider }
		deviceReachabilityService.start()
		OCConnection.certificateValidationHandler = { _, request, certificate, _, proceedHandler in
			let ok = CertificateValidationService.shared.validatePinnedCertificate(
				serverCertificate: certificate,
				host: request.hostname,
				validateHost: false
			)
			if ok {
				proceedHandler(true, nil)
				return
			}

			// Not pinned: ask user whether to trust this server, and persist decision.
			DeviceCertificateTrustPrompt.askToTrust(host: request.hostname, certificate: certificate) { accepted in
				if accepted {
					proceedHandler(true, nil)
				} else {
					proceedHandler(false, NSError(ocError: .requestServerCertificateRejected))
				}
			}
		}
	}
}
