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
	}

	public func setup() {
		Task { OCConnection.defaultBaseURLProvider = await deviceReachabilityService.urlProvider }
		deviceReachabilityService.start()
	}
}
