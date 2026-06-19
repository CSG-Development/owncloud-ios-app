import Foundation
import Combine
import ownCloudSDK

public extension Notification.Name {
	/// Posted on main when `HCContext.lastRemoteBaseURL` changes (reachability best path).
	static let hcRemoteBaseURLDidChange = Notification.Name("HCRemoteBaseURLDidChange")
	/// Posted on main when the favorite device's best connection URL changes.
	static let hcBestBaseURLDidChange = Notification.Name("HCBestBaseURLDidChange")
}

public enum HCBestBaseURLNotification {
	public static let urlUserInfoKey = "url"
}

private enum Constants {
	static let remoteAccessBaseURL = URL(
		string: "https://hc-remote-access-env-https.eba-a2nvhpbm.us-west-2.elasticbeanstalk.com:443/api"
	)!
}

public final class HCContext {
	public static let shared = HCContext()

	/// True for File Provider and other app extensions — separate process, no snackbar UI.
	public static var isAppExtension: Bool {
		Bundle.main.bundlePath.hasSuffix(".appex")
	}

	public let preferences: HCPreferences
	public let remoteAccessService: RemoteAccessService
	public let deviceReachabilityService: DeviceReachabilityService
	public let mdnsService: MDNSService
	public let remoteAccessTokenStore: RemoteAccessTokenStore
	public let networkAvailabilityMonitor: NetworkAvailabilityMonitor
	public let connectivityStateCoordinator: ConnectivityStateCoordinator
	public var emailVerificationHandler: (@MainActor (_ email: String, _ completion: @escaping (Bool) -> Void) -> Void)?

	// Hack to provide this info for related data sources.
	// Use `RemoteAccessSharingURLResolver` directly if possible.
	public var lastRemoteBaseURL: URL?

	/// Best URL for the favorite device (local or remote). Always queries the URL provider
	/// directly so callers see the live value, not a cached copy that depends on
	/// notification-observer ordering.
	public var currentBestBaseURL: URL? {
		deviceReachabilityService.urlProvider.currentBaseURL()
	}

	private var networkFailureObserver: NSObjectProtocol?
	private var cancellables = Set<AnyCancellable>()
	private let reachabilityObserver: DefaultReachabilityObserver

	public init() {
		self.preferences = HCPreferences()
		self.remoteAccessTokenStore = RemoteAccessTokenStore()
		self.reachabilityObserver = DefaultReachabilityObserver()

		self.remoteAccessService = RemoteAccessService(
			api: RemoteAccessAPI(baseURL: Constants.remoteAccessBaseURL),
			tokenStore: remoteAccessTokenStore
		)
		self.mdnsService = MDNSService()
		self.networkAvailabilityMonitor = NetworkAvailabilityMonitor.shared
		self.connectivityStateCoordinator = ConnectivityStateCoordinator.shared

		self.deviceReachabilityService = DeviceReachabilityService(
			reachability: reachabilityObserver,
			remoteAccessService: remoteAccessService,
			mdnsService: mdnsService,
			preferences: preferences,
			connectivityCoordinator: connectivityStateCoordinator
		)

		deviceReachabilityService.events
			.receive(on: DispatchQueue.main)
			.sink { [weak self] event in
				guard case let .remoteBaseURLChanged(url) = event else { return }
				self?.lastRemoteBaseURL = url
				NotificationCenter.default.post(name: .hcRemoteBaseURLDidChange, object: nil)
				guard url != nil, !Self.isAppExtension else { return }
				Task { [weak self] in
					guard let self,
					      await self.deviceReachabilityService.isPreferredDeviceReachable() else {
						Self.logConnectivity("remote base URL changed but device not reachable — skipping")
						return
					}
					await self.connectivityStateCoordinator.noteActivePathAvailable()
				}
			}
			.store(in: &cancellables)
	}

	/// Resets connectivity state on logout so the next login starts from a clean session.
	public func resetConnectivityOnLogout() async {
		Self.logConnectivity("logout reset")
		preferences.clearConnectedDeviceSession()
		await connectivityStateCoordinator.reset()
		await deviceReachabilityService.resetState()
		await networkAvailabilityMonitor.reset()
	}

	public func setup() {
		OCConnection.defaultBaseURLProvider = deviceReachabilityService.urlProvider
		reachabilityObserver.start()
		deviceReachabilityService.start()
		Self.logConnectivity("setup starting")

		Task {
			await configureConnectivityCoordinator()
			let initialState = await reachabilityObserver.awaitFirstReading()
			Self.logConnectivity(
				"initial reachability interface=\(initialState.interface.rawValue) "
					+ "reachable=\(initialState.isReachable) localPaths=\(initialState.allowsLocalPaths)"
			)
			await connectivityStateCoordinator.installLifecycleObserversIfNeeded()
			await connectivityStateCoordinator.refreshSessionActive()
			await deviceReachabilityService.handleNetworkPathSideEffects(initialState)
			await connectivityStateCoordinator.handleNetworkState(initialState)
			await deviceReachabilityService.performColdLaunchPathDetection()
			Self.logConnectivity("setup complete")
		}

		reachabilityObserver.updatesPublisher
			.removeDuplicates(by: { $0.interface == $1.interface && $0.isReachable == $1.isReachable })
			.sink { [deviceReachabilityService, connectivityStateCoordinator] state in
				Task {
					await deviceReachabilityService.handleNetworkPathSideEffects(state)
					await connectivityStateCoordinator.handleNetworkState(state)
				}
			}
			.store(in: &cancellables)

		// status.php polling & similar: SDK does not call OCCoreDelegate handleError for these.
		if networkFailureObserver == nil {
			networkFailureObserver = NotificationCenter.default.addObserver(
				forName: NSNotification.Name.OCNetworkingFailureReachability,
				object: nil,
				queue: .main
			) { note in
				if let error = note.userInfo?["error"] as? Error {
					HCContext.shared.deviceReachabilityService.reportOperationError(error)
				}
			}
		}

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

	private func configureConnectivityCoordinator() async {
		await connectivityStateCoordinator.configure(
			preferences: preferences,
			reachability: reachabilityObserver,
			toastMonitor: networkAvailabilityMonitor,
			remoteAccessService: remoteAccessService,
			pathRecoveryHandler: { [deviceReachabilityService] in
				await deviceReachabilityService.forceReloadDevices()
			},
			supplementalProbePaths: { [deviceReachabilityService] in
				await deviceReachabilityService.supplementalProbePaths()
			},
			isPreferredDeviceReachable: { [deviceReachabilityService] in
				await deviceReachabilityService.isPreferredDeviceReachable()
			}
		)
		if Self.isAppExtension {
			await connectivityStateCoordinator.setSnackbarDrivingEnabled(false)
		}
	}

	private static func logConnectivity(_ message: String) {
		Log.debug("[STX-CONN]: \(message)")
	}
}
