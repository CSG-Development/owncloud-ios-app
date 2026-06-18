import Foundation
import ownCloudSDK

/// Single source of truth for network + device connectivity. Drives snackbars and the SDK gate.
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
	private var supplementalProbePaths: (() async -> [RemoteDevice.Path])?
	private var isPreferredDeviceReachable: (() async -> Bool)?
	private var pipelineReloadDepth = 0
	private var toastPublishTask: Task<Void, Never>?
	private var snackbarDrivingEnabled = true
	private var lastObservedInterface: NetworkState.Interface?

	public init(pathProber: PathProber = PathProber()) {
		self.pathProber = pathProber
	}

	public var currentDeviceAccess: DeviceAccessState { session.deviceAccess }
	public var isSessionActive: Bool { !session.isLoggedOut }
	public var isAwaitingRAAuthentication: Bool { session.isAwaitingRemoteAuthentication }
	public var isBootstrapComplete: Bool { session.isActive }

	public func setSnackbarDrivingEnabled(_ enabled: Bool) {
		snackbarDrivingEnabled = enabled
		Self.log("snackbar driving \(enabled ? "enabled" : "disabled")")
	}

	public func noteLaunchDetectionComplete() async {
		let transition = session.handle(.markLaunchDetectionComplete)
		guard transition.launchDetectionMarkedComplete else { return }
		await tryFinishBootstrap()
	}

	public func noteLoginBootstrapComplete() async {
		guard session.shouldCompleteLoginBootstrap else {
			Self.log("login bootstrap complete ignored (phase=\(session.connectivity))")
			return
		}
		Self.log("login bootstrap complete")
		await finishBootstrap()
	}

	public func configure(
		preferences: HCPreferences,
		reachability: ReachabilityObserving,
		toastMonitor: NetworkAvailabilityMonitor,
		remoteAccessService: RemoteAccessService,
		pathRecoveryHandler: @escaping () async throws -> Void,
		supplementalProbePaths: (() async -> [RemoteDevice.Path])? = nil,
		isPreferredDeviceReachable: (() async -> Bool)? = nil
	) {
		self.preferences = preferences
		self.reachability = reachability
		self.toastMonitor = toastMonitor
		self.remoteAccessService = remoteAccessService
		self.pathRecoveryHandler = pathRecoveryHandler
		self.supplementalProbePaths = supplementalProbePaths
		self.isPreferredDeviceReachable = isPreferredDeviceReachable
		if session.isLoggedOut, ConnectivitySessionState.hasPersistedDeviceSession(preferences: preferences) {
			_ = session.handle(.activateSession(.launchDetection))
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
			_ = session.handle(.activateSession(.launchDetection))
			publish()
			Task { await self.tryFinishBootstrap() }
		} else {
			_ = session.handle(.deactivateSession)
			publish()
		}
	}

	public func setNetworkReachable(_ reachable: Bool) {
		let transition = session.handle(.setNetworkReachable(reachable))
		guard transition.connectivityChanged else { return }
		Self.log("network \(reachable ? "up" : "down")")
		publish()
	}

	public func invalidateConfiguredProbePaths() {
		probePathCache.invalidate()
	}

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

		let localAllowed = state.allowsLocalPaths
		if interfaceChanged {
			probePathCache.invalidate()
		}
		if interfaceChanged, hasConfiguredPaths(), isBootstrapComplete {
			Self.log(
				"interface changed → path recovery "
					+ "(\(previousInterface?.rawValue ?? "?")→\(state.interface.rawValue))"
			)
			await runPathRecovery(
				localPathsAllowed: localAllowed,
				skipInitialProbe: true,
				localPathsFailed: !localAllowed
			)
		} else if state.isReachable, !wasReachable, probeScheduler.hostScreenActive, probeScheduler.isForeground {
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

	public func setPipelineReloading(_ active: Bool) {
		if active {
			pipelineReloadDepth += 1
		} else {
			pipelineReloadDepth = max(0, pipelineReloadDepth - 1)
		}
		publish()
	}

	public func applyCatalogSnapshot(_ snapshot: CatalogReachabilitySnapshot) {
		guard !session.isLoggedOut else {
			Self.log("catalog snapshot ignored (logged out)")
			return
		}
		if session.isAwaitingRemoteAuthentication {
			Self.log("catalog snapshot ignored (awaiting RA auth)")
			return
		}
		if !snapshot.hasDeviceCN {
			Self.log("catalog snapshot→disconnected (no device CN)")
			applyDeviceAccess(.disconnected, policy: .catalogSync)
			return
		}
		if snapshot.isReachable {
			Self.log("catalog snapshot→connected")
			applyDeviceAccess(.connected, policy: .catalogSync)
		} else if session.deviceAccess == .connecting || session.deviceAccess == .connected {
			Self.log("catalog snapshot→disconnected (unreachable)")
			applyDeviceAccess(.disconnected, policy: .catalogSync)
		}
	}

	public func noteCatalogReloadStarting() {
		probePathCache.invalidate()
		Self.log("catalog reload starting — showing connecting UI")
		applyDeviceAccess(.connecting, policy: .normal)
	}

	public func noteRAAuthenticationFailed() {
		Self.log("RA authentication failed")
		applyDeviceAccess(.disconnected, policy: .duringRAAuth)
	}

	public func reset() {
		Self.log("reset")
		recoveryRunner.reset()
		toastPublishTask?.cancel()
		toastPublishTask = nil
		probeScheduler.reset()
		probePathCache.invalidate()
		lastObservedInterface = nil
		pipelineReloadDepth = 0
		_ = session.handle(.reset(networkReachable: reachability?.currentState.isReachable ?? true))
		publish()
	}

	public func beginSession() {
		guard session.isLoggedOut else {
			Self.log("beginSession ignored (phase=\(session.connectivity))")
			return
		}
		let bootstrap: ConnectivityBootstrapWait =
			session.coldLaunchDetectionComplete ? .loginCatalog : .launchDetection
		Self.log("beginSession→bootstrapping(\(bootstrap))")
		_ = session.handle(.activateSession(bootstrap))
		publish()
		Task { await self.tryFinishBootstrap() }
	}

	public func evaluateConfiguredPaths(localPathsAllowed: Bool) async {
		await evaluateAndRecover(isPeriodic: true, localPathsAllowed: localPathsAllowed)
	}

	public func retry(localPathsAllowed: Bool? = nil) async {
		Self.log("user retry tapped")
		await runPathRecovery(localPathsAllowed: localPathsAllowed ?? currentLocalPathsAllowed())
	}

	public func triggerPathRecoveryFromError(localPathsAllowed: Bool) async {
		guard isBootstrapComplete else {
			Self.log("transport recovery skipped (bootstrap incomplete)")
			return
		}
		Log.debug("[STX-RA]: Transport failure → coordinator path recovery")
		Self.log("transport recovery started")
		await runPathRecovery(localPathsAllowed: localPathsAllowed, fromTransportError: true)
	}

	public func runPathRecovery(
		localPathsAllowed: Bool,
		skipInitialProbe: Bool = false,
		localPathsFailed: Bool = false,
		fromTransportError: Bool = false,
		alternatePathReachable: Bool = false
	) async {
		switch session.checkRecoveryEligibility() {
			case .eligible:
				break
			case .ineligible(let reason):
				Self.log("recovery skipped (\(reason))")
				return
		}

		let request = ConnectivityRecoveryRequest(
			localPathsAllowed: localPathsAllowed,
			skipInitialProbe: skipInitialProbe,
			localPathsFailed: localPathsFailed,
			fromTransportError: fromTransportError,
			alternatePathReachable: alternatePathReachable
		)

		await recoveryRunner.run(
			request: request,
			session: session,
			snackbarDrivingEnabled: snackbarDrivingEnabled,
			dependencies: recoveryDependencies(),
			perform: ConnectivityRecoveryRunner.performRecovery
		)
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
		applyDeviceAccess(.connected, policy: .pathAvailable)
	}

	func setConnectingForAlternateProbe() {
		applyDeviceAccess(.connecting, policy: .normal)
	}

	// MARK: - Private

	private func handleAppForeground(_ foreground: Bool) async {
		probeScheduler.setAppForeground(foreground)
		Self.log("app foreground=\(foreground)")
		await reconcileProbeLoop()
	}

	private func tryFinishBootstrap() async {
		guard session.shouldCompleteLaunchBootstrap else { return }
		await finishBootstrap()
	}

	private func finishBootstrap() async {
		guard session.handle(.finishBootstrap).connectivityChanged else { return }
		Self.log("bootstrap complete — snackbars enabled")
		publish()
		await evaluateAndRecover(isPeriodic: false, localPathsAllowed: currentLocalPathsAllowed())
		await reconcileProbeLoop()
	}

	private func evaluateAndRecover(isPeriodic: Bool, localPathsAllowed: Bool) async {
		let eligibility = isPeriodic
			? session.checkPeriodicProbeEligibility(recoveryInFlight: recoveryRunner.isInFlight)
			: session.checkPostBootstrapProbeEligibility()
		switch eligibility {
			case .eligible:
				break
			case .ineligible(let reason):
				if isPeriodic {
					Self.log("probe skipped (\(reason))")
				} else {
					publish()
				}
				return
		}
		guard let preferences else {
			if isPeriodic { Self.log("periodic probe skipped (preferences not configured)") }
			publish()
			return
		}

		let paths = await ConnectivityRecoveryRunner.configuredProbePaths(
			preferences: preferences,
			dependencies: recoveryDependencies()
		)
		if paths.isEmpty {
			await handleEmptyProbePaths(localPathsAllowed: localPathsAllowed)
			return
		}

		let currentPathKey = preferences.currentConnectedDevice?.lastSuccessfulPathKey
		let result = await ConnectivityRecoveryRunner.probeConfiguredPaths(
			paths: paths,
			currentPathKey: currentPathKey,
			localPathsAllowed: localPathsAllowed,
			dependencies: recoveryDependencies()
		)
		ConnectivityEventLog.probeResult(
			result,
			pathCount: paths.count,
			currentPathKey: currentPathKey,
			localPathsAllowed: localPathsAllowed
		)
		await handleConfiguredProbeResult(result, localPathsAllowed: localPathsAllowed)
	}

	private func handleEmptyProbePaths(localPathsAllowed: Bool) async {
		Self.log("probe paths empty — checking catalog reachability")
		if await preferredDeviceIsReachable() {
			applyDeviceAccess(.connected, policy: .pathEvidence)
			await runPathRecovery(localPathsAllowed: localPathsAllowed, skipInitialProbe: true)
		} else {
			await runPathRecovery(localPathsAllowed: localPathsAllowed, skipInitialProbe: true, localPathsFailed: true)
		}
	}

	private func handleConfiguredProbeResult(
		_ result: PathConnectivityProbeResult,
		localPathsAllowed: Bool
	) async {
		switch result {
			case .currentPathReachable:
				applyDeviceAccess(.connected, policy: .pathEvidence)
			case .alternatePathReachable:
				await runPathRecovery(
					localPathsAllowed: localPathsAllowed,
					skipInitialProbe: true,
					alternatePathReachable: true
				)
			case .allUnreachable:
				if await preferredDeviceIsReachable() {
					applyDeviceAccess(.connected, policy: .pathEvidence)
					await runPathRecovery(localPathsAllowed: localPathsAllowed, skipInitialProbe: true)
				} else {
					await runPathRecovery(localPathsAllowed: localPathsAllowed, skipInitialProbe: true, localPathsFailed: true)
				}
		}
	}

	private func applyDeviceAccess(_ state: DeviceAccessState, policy: ConnectivityAccessPolicy) {
		let transition = session.handle(.applyDeviceAccess(state, policy))
		guard transition.deviceAccessChanged || transition.connectivityChanged else { return }
		publish()
	}

	private func publish() {
		let presenter = ConnectivityBannerPresenter(
			snackbarDrivingEnabled: snackbarDrivingEnabled,
			connectivity: session.connectivity,
			pipelineReloading: pipelineReloadDepth > 0
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
	}

	private func endRemoteAuthenticationOnSession(device: DeviceAccessState) {
		_ = session.handle(.endRemoteAuthentication(device))
	}

	private func recoveryDependencies() -> ConnectivityRecoveryRunner.Dependencies {
		ConnectivityRecoveryRunner.Dependencies(
			pathProber: pathProber,
			preferences: preferences,
			remoteAccessService: remoteAccessService,
			supplementalProbePaths: supplementalProbePaths,
			isPreferredDeviceReachable: isPreferredDeviceReachable,
			pathRecoveryHandler: pathRecoveryHandler,
			configuredProbePaths: { [weak self] preferences in
				guard let self else { return [] }
				return await self.probePathCache.configuredPaths(
					preferences: preferences,
					supplementalProbePaths: { await self.supplementalProbePaths?() ?? [] }
				)
			},
			requestRAAuthentication: { [weak self] email in
				await self?.requestRAAuthentication(email: email) ?? false
			},
			recoveryEmail: { [preferences] in
				ConnectivityRecoveryRunner.recoveryEmail(preferences: preferences)
			},
			setConnectingForAlternateProbe: { [weak self] in
				await self?.setConnectingForAlternateProbe()
			},
			applyDeviceAccess: { [weak self] state, policy in
				await self?.applyDeviceAccess(state, policy: policy)
			},
			currentDeviceAccess: { [weak self] in
				await self?.session.deviceAccess ?? .connected
			},
			beginRemoteAuthentication: { [weak self] in
				await self?.beginRemoteAuthenticationOnSession()
			},
			endRemoteAuthentication: { [weak self] device in
				await self?.endRemoteAuthenticationOnSession(device: device)
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

	private func preferredDeviceIsReachable() async -> Bool {
		await (isPreferredDeviceReachable?() ?? false)
	}

	private func hasConfiguredPaths() -> Bool {
		preferences?.currentConnectedDevice != nil
	}

	private func probeEnvironment() -> ConnectivityProbeScheduler.Environment {
		ConnectivityProbeScheduler.Environment(
			networkReachable: session.networkReachable,
			hasConfiguredPaths: hasConfiguredPaths(),
			isBootstrapComplete: isBootstrapComplete
		)
	}

	private func reconcileProbeLoop() async {
		await probeScheduler.reconcile(
			environment: probeEnvironment(),
			log: { Self.log($0) },
			runRound: { [weak self] in
				await self?.runPeriodicProbeRoundIfReady()
			}
		)
	}

	private func runPeriodicProbeRoundIfReady() async {
		guard probeScheduler.canRunPeriodicProbe(in: probeEnvironment()) else { return }
		Log.debug("[STX-CONN]: periodic probe round started")
		await evaluateConfiguredPaths(localPathsAllowed: currentLocalPathsAllowed())
	}

	private static func log(_ message: String) {
		ConnectivityEventLog.log(message)
	}
}
