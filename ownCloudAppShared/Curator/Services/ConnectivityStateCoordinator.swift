import Foundation
import ownCloudSDK

/// Single source of truth for network + device connectivity. Drives the snackbar and the SDK gate.
///
/// Every signal that could affect connectivity (network change, app foreground, the periodic
/// tick, a Retry tap, a transport failure, mDNS / static-address discovery, login) funnels
/// through `evaluate(reason:)`. That serialized evaluation is the *only* writer of
/// `DeviceAccessState`, which is why there is no longer an access-policy arbitration layer or a
/// second catalog-snapshot writer.
public final actor ConnectivityStateCoordinator {
	public static let shared = ConnectivityStateCoordinator()

	private var session = ConnectivitySessionState()
	private var probePathCache = ConnectivityProbePathCache()
	private var probeScheduler = ConnectivityProbeScheduler()
	private var recoveryRunner = ConnectivityRecoveryRunner()
	private let lifecycleObserver = ConnectivityLifecycleObserver()

	private var toastMonitor: NetworkAvailabilityMonitor?
	private var preferences: HCPreferences?
	private var reachability: ReachabilityObserving?
	private var remoteAccessService: RemoteAccessService?
	private let pathProber: PathProber
	private var pathRecoveryHandler: (() async throws -> Void)?
	private var allProbePaths: (() async -> [RemoteDevice.Path])?
	private var isPreferredDeviceReachable: (() async -> Bool)?
	private var applyBestProbedPath: (@Sendable (RemoteDevice.Path) async -> Void)?
	private var toastPublishTask: Task<Void, Never>?
	private var snackbarDrivingEnabled = true
	private var lastObservedInterface: NetworkState.Interface?
	private var banner = ConnectivityBannerPresentation()
	private var hasCompletedInitialConnectivityEvaluation = false

	public init(pathProber: PathProber = PathProber()) {
		self.pathProber = pathProber
	}

	public var currentDeviceAccess: DeviceAccessState { session.deviceAccess }
	public var isSessionActive: Bool { !session.isLoggedOut }
	public var isAwaitingRAAuthentication: Bool { session.isAwaitingRemoteAuthentication }

	public func setSnackbarDrivingEnabled(_ enabled: Bool) {
		snackbarDrivingEnabled = enabled
		Self.log("snackbar driving \(enabled ? "enabled" : "disabled")")
	}

	public func configure(
		preferences: HCPreferences,
		reachability: ReachabilityObserving,
		toastMonitor: NetworkAvailabilityMonitor,
		remoteAccessService: RemoteAccessService,
		pathRecoveryHandler: @escaping () async throws -> Void,
		allProbePaths: (() async -> [RemoteDevice.Path])? = nil,
		isPreferredDeviceReachable: (() async -> Bool)? = nil,
		applyBestProbedPath: (@Sendable (RemoteDevice.Path) async -> Void)? = nil
	) {
		self.preferences = preferences
		self.reachability = reachability
		self.toastMonitor = toastMonitor
		self.remoteAccessService = remoteAccessService
		self.pathRecoveryHandler = pathRecoveryHandler
		self.allProbePaths = allProbePaths
		self.isPreferredDeviceReachable = isPreferredDeviceReachable
		self.applyBestProbedPath = applyBestProbedPath
		if session.isLoggedOut, ConnectivitySessionState.hasPersistedDeviceSession(preferences: preferences) {
			_ = session.handle(.activateSession)
			publish()
		}
		Self.log("configured (phase=\(session.connectivity))")
	}

	public func refreshSessionActive() {
		guard let preferences else { return }
		let active = ConnectivitySessionState.hasPersistedDeviceSession(preferences: preferences)
			|| !OCBookmarkManager.shared.bookmarks.isEmpty
		Self.log("refreshSession active=\(active) phase=\(session.connectivity)")
		if active {
			_ = session.handle(.activateSession)
			publish()
		} else {
			_ = session.handle(.deactivateSession)
			publish()
		}
	}

	public func setNetworkReachable(_ reachable: Bool) {
		let transition = session.handle(.setNetworkReachable(reachable))
		guard transition.connectivityChanged else { return }
		Self.log("network \(reachable ? "up" : "down")")
		if !reachable {
			banner.clearTransientOnNetworkDown()
		}
		publish()
	}

	public func invalidateConfiguredProbePaths() {
		probePathCache.invalidate()
	}

	/// The single network-change reactive entry. Updates the reachable flag, then evaluates
	/// when the interface changed or the network just came back.
	public func handleNetworkState(_ state: NetworkState) async {
		let previousInterface = lastObservedInterface
		let interfaceChanged = previousInterface.map { $0 != state.interface } ?? false
		lastObservedInterface = state.interface
		let wasReachable = session.networkReachable
		Self.log(
			"network state interface=\(state.interface.rawValue) reachable=\(state.isReachable) "
				+ "localPaths=\(state.allowsLocalPaths)"
				+ (interfaceChanged ? " (changed)" : "")
		)
		setNetworkReachable(state.isReachable)

		if interfaceChanged {
			probePathCache.invalidate()
		}
		if interfaceChanged, hasConfiguredPaths() {
			Self.log(
				"interface changed → evaluate "
					+ "(\(previousInterface?.rawValue ?? "?")→\(state.interface.rawValue))"
			)
			await evaluate(reason: .networkChanged)
		} else if state.isReachable, !wasReachable, probeScheduler.isForeground {
			Self.log("network restored — scheduling immediate probe")
			probeScheduler.scheduleImmediateProbeOnNetworkRestore()
		}

		await reconcileProbeLoop()
	}

	public func installLifecycleObserversIfNeeded() {
		lifecycleObserver.installIfNeeded { [weak self] foreground in
			guard let self else { return }
			Task { await self.handleAppForeground(foreground) }
		}
	}

	public func setHostScreenActive(_ active: Bool) async {
		probeScheduler.setHostScreenActive(active)
		Self.log("host screen active=\(active)")
		await reconcileProbeLoop()
	}

	public func noteRAAuthenticationFailed() {
		Self.log("RA authentication failed")
		finishDisconnected()
	}

	public func reset() {
		Self.log("reset")
		recoveryRunner.reset()
		toastPublishTask?.cancel()
		toastPublishTask = nil
		probeScheduler.reset()
		probePathCache.invalidate()
		lastObservedInterface = nil
		banner.reset()
		hasCompletedInitialConnectivityEvaluation = false
		_ = session.handle(.reset(networkReachable: reachability?.currentState.isReachable ?? true))
		publish()
	}

	public func beginSession() {
		guard session.isLoggedOut else {
			Self.log("beginSession ignored (phase=\(session.connectivity))")
			return
		}
		Self.log("beginSession→active")
		_ = session.handle(.activateSession)
		publish()
		Task {
			await self.evaluate(reason: .sessionStart)
		}
	}

	/// Call after login path selection succeeded. The login probe already verified reachability;
	/// avoid an immediate full catalog reload which would clear that state and stall on
	/// "Finding network".
	public func activateAfterLogin() async {
		guard session.isLoggedOut else {
			Self.log("activateAfterLogin ignored (phase=\(session.connectivity))")
			return
		}
		Self.log("activateAfterLogin→active (login path verified)")
		_ = session.handle(.activateSession)
		invalidateConfiguredProbePaths()
		finishConnected()
		await reconcileProbeLoop()
	}

	public func refreshSessionAfterBookmarkAdded() async {
		refreshSessionActive()
		invalidateConfiguredProbePaths()
		await evaluate(reason: .discovery)
	}

	public func retry() async {
		Self.log("user retry tapped")
		banner.beginRetrySearch()
		invalidateConfiguredProbePaths()
		publish()
		await evaluate(reason: .retry)
	}

	public func triggerPathRecoveryFromError() async {
		Log.debug("[STX-RA]: Transport failure → coordinator evaluate")
		await evaluate(reason: .transportError)
	}

	/// The single connectivity evaluator. All triggers route here. Serialized by
	/// `ConnectivityRecoveryRunner`, so overlapping requests coalesce.
	public func evaluate(reason: ConnectivityEvaluateReason) async {
		switch session.checkRecoveryEligibility() {
			case .eligible:
				break
			case .ineligible(let why):
				Self.log("evaluate skipped (\(why)) reason=\(reason.rawValue)")
				return
		}

		Self.log("evaluate (reason=\(reason.rawValue))")
		let context = ConnectivityEvaluationContext.make(
			for: reason,
			deviceAccess: session.deviceAccess,
			connectionLostLatched: banner.connectionLostLatched,
			hasCompletedInitialEvaluation: hasCompletedInitialConnectivityEvaluation
		)
		if context.retainSDKOnActiveConnection, session.deviceAccess == .connected {
			banner.sdkConnectionRetained = true
		}
		await recoveryRunner.run(
			localPathsAllowed: currentLocalPathsAllowed(),
			session: session,
			snackbarDrivingEnabled: snackbarDrivingEnabled,
			context: context,
			dependencies: recoveryDependencies(),
			perform: ConnectivityRecoveryRunner.performEvaluate
		)
		if reason == .discovery || reason == .sessionStart {
			hasCompletedInitialConnectivityEvaluation = true
		}
		await reconcileProbeLoop()
	}

	public func noteActivePathAvailable() {
		switch session.checkRecoveryEligibility() {
			case .eligible:
				break
			case .ineligible(let reason):
				Self.log("path available ignored (\(reason))")
				return
		}
		Self.log("active path available — marking connected")
		finishConnected()
	}

	// MARK: - Private

	private func handleAppForeground(_ foreground: Bool) async {
		probeScheduler.setAppForeground(foreground)
		Self.log("app foreground=\(foreground)")
		await reconcileProbeLoop()
	}

	private func showFindingNetworkBanner() {
		guard banner.showFindingNetwork() else { return }
		Self.log("banner→findingNetwork (search started)")
		publish()
	}

	private func finishConnected() {
		banner.finishConnected()
		_ = session.handle(.applyDeviceAccess(.connected))
		publish()
	}

	private func finishDisconnected() {
		banner.finishDisconnected()
		_ = session.handle(.applyDeviceAccess(.disconnected))
		publish()
	}

	private func publish() {
		let presenter = ConnectivityBannerPresenter(
			snackbarDrivingEnabled: snackbarDrivingEnabled,
			connectivity: session.connectivity,
			banner: banner
		)
		SDKDeviceAvailabilityGate.shared.setDeviceConnected(presenter.sdkConnected)

		guard let toastMonitor else { return }
		let (kind, suppressReason) = presenter.bannerKind()

		if let suppressReason {
			Self.log(
				"banner hidden (device=\(session.deviceAccess) network=\(session.networkReachable ? "up" : "down") "
					+ "reason=\(suppressReason) sdk=\(presenter.sdkConnected ? "online" : "offline"))"
			)
		} else {
			Self.log(
				"banner→\(ConnectivityBannerPresenter.bannerLabel(kind)) (device=\(session.deviceAccess) "
					+ "network=\(session.networkReachable ? "up" : "down") "
					+ "sdk=\(presenter.sdkConnected ? "online" : "offline"))"
			)
		}

		toastPublishTask?.cancel()
		toastPublishTask = Task {
			guard !Task.isCancelled else { return }
			await toastMonitor.setVisibility(kind)
		}
	}

	private func beginRemoteAuthenticationOnSession() {
		_ = session.handle(.beginRemoteAuthentication)
		publish()
	}

	private func endRemoteAuthenticationOnSession(device: DeviceAccessState) {
		_ = session.handle(.endRemoteAuthentication(device))
		publish()
	}

	private func recoveryDependencies() -> ConnectivityRecoveryRunner.Dependencies {
		ConnectivityRecoveryRunner.Dependencies(
			pathProber: pathProber,
			preferences: preferences,
			remoteAccessService: remoteAccessService,
			allProbePaths: allProbePaths,
			isPreferredDeviceReachable: isPreferredDeviceReachable,
			pathRecoveryHandler: pathRecoveryHandler,
			configuredProbePaths: { [weak self] preferences in
				guard let self else { return [] }
				return await self.probePathCache.configuredPaths(
					preferences: preferences,
					allProbePaths: { await self.allProbePaths?() ?? [] }
				)
			},
			applyBestProbedPath: { [weak self] path in
				await self?.applyBestProbedPath?(path)
			},
			requestRAAuthentication: { [weak self] email in
				await self?.requestRAAuthentication(email: email) ?? false
			},
			recoveryEmail: { [preferences] in
				ConnectivityRecoveryRunner.recoveryEmail(preferences: preferences)
			},
			beginRemoteAuthentication: { [weak self] in
				await self?.beginRemoteAuthenticationOnSession()
			},
			endRemoteAuthentication: { [weak self] device in
				await self?.endRemoteAuthenticationOnSession(device: device)
			},
			showFindingNetworkBanner: { [weak self] in
				await self?.showFindingNetworkBanner()
			},
			finishConnected: { [weak self] in
				await self?.finishConnected()
			},
			finishDisconnected: { [weak self] in
				await self?.finishDisconnected()
			},
			log: { Self.log($0) }
		)
	}

	private func requestRAAuthentication(email: String) async -> Bool {
		guard let handler = HCContext.shared.emailVerificationHandler else {
			Log.debug("[STX-RA]: RA verification handler is not configured.")
			return false
		}
		return await withCheckedContinuation { continuation in
			Task { @MainActor in
				handler(email) { isAuthenticated in
					continuation.resume(returning: isAuthenticated)
				}
			}
		}
	}

	private func currentLocalPathsAllowed() -> Bool {
		reachability?.currentState.allowsLocalPaths ?? true
	}

	private func hasConfiguredPaths() -> Bool {
		guard let preferences else { return false }
		// Local/mDNS-only logins may have favoriteDeviceCN without currentConnectedDevice
		// (LoginViewModel only persisted remote devices). Supplemental probes still work via CN.
		return preferences.currentConnectedDevice != nil || preferences.favoriteDeviceCN != nil
	}

	private func probeEnvironment() -> ConnectivityProbeScheduler.Environment {
		ConnectivityProbeScheduler.Environment(
			networkReachable: session.networkReachable,
			hasConfiguredPaths: hasConfiguredPaths()
		)
	}

	private func reconcileProbeLoop() async {
		await probeScheduler.reconcile(
			log: { Self.log($0) },
			runRound: { [weak self] in
				await self?.runPeriodicProbeRoundIfReady()
			}
		)
	}

	private func runPeriodicProbeRoundIfReady() async {
		let environment = probeEnvironment()
		guard probeScheduler.canRunPeriodicProbe(in: environment) else {
			Self.log(
				"periodic probe round skipped (host=\(probeScheduler.hostScreenActive) "
					+ "fg=\(probeScheduler.isForeground) network=\(environment.networkReachable) "
					+ "paths=\(environment.hasConfiguredPaths))"
			)
			return
		}
		switch session.checkPeriodicProbeEligibility(recoveryInFlight: recoveryRunner.isInFlight) {
			case .eligible:
				break
			case .ineligible(let reason):
				Self.log("periodic probe skipped (\(reason))")
				return
		}
		Log.debug("[STX-CONN]: periodic probe round started")
		await evaluate(reason: .periodic)
	}

	private static func log(_ message: String) {
		ConnectivityEventLog.log(message)
	}
}
