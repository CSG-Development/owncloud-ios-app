import Foundation
import ownCloudSDK

public enum DeviceAccessState: Sendable, Equatable {
	case connected
	case connecting
	case disconnected
}

/// Single source of truth for network + device connectivity. Drives snackbars and the SDK gate.
public final actor ConnectivityStateCoordinator {
	public static let shared = ConnectivityStateCoordinator()

	private var networkReachable = true
	private var deviceAccess: DeviceAccessState = .connected
	private var sessionActive = false

	private var toastMonitor: NetworkAvailabilityMonitor?
	private var preferences: HCPreferences?
	private var reachability: ReachabilityObserving?
	private var remoteAccessService: RemoteAccessService?
	private let pathProber: PathProber
	private var pathRecoveryHandler: ((Bool) async -> Void)?
	private var onBootstrapComplete: (() async -> Void)?
	private var supplementalProbePaths: (() async -> [RemoteDevice.Path])?
	private var isPreferredDeviceReachable: (() async -> Bool)?
	private var lastErrorRecoveryAt: Date?
	private let errorRecoveryThrottleSeconds: TimeInterval = 60
	private var pathRecoveryTask: Task<Void, Never>?
	private var awaitingRAAuthentication = false
	/// While true, device-level snackbars are hidden and pessimistic access downgrades are ignored
	/// until cold-launch path detection has populated the catalog.
	private var suppressConnectivitySnackbar = false
	private var launchDetectionComplete = false
	private var toastPublishGeneration: UInt = 0

	public init(pathProber: PathProber = PathProber()) {
		self.pathProber = pathProber
	}

	public var currentDeviceAccess: DeviceAccessState { deviceAccess }

	public var isSessionActive: Bool { sessionActive }

	public var isAwaitingRAAuthentication: Bool { awaitingRAAuthentication }

	public var isBootstrapComplete: Bool { !suppressConnectivitySnackbar }

	/// Called when `DeviceReachabilityService` finishes cold-launch path detection.
	public func noteLaunchDetectionComplete() async {
		launchDetectionComplete = true
		await finishBootstrapIfReady()
	}
	public func configure(
		preferences: HCPreferences,
		reachability: ReachabilityObserving,
		toastMonitor: NetworkAvailabilityMonitor,
		remoteAccessService: RemoteAccessService,
		pathRecoveryHandler: @escaping (Bool) async -> Void,
		onBootstrapComplete: (() async -> Void)? = nil,
		supplementalProbePaths: (() async -> [RemoteDevice.Path])? = nil,
		isPreferredDeviceReachable: (() async -> Bool)? = nil
	) {
		self.preferences = preferences
		self.reachability = reachability
		self.toastMonitor = toastMonitor
		self.remoteAccessService = remoteAccessService
		self.pathRecoveryHandler = pathRecoveryHandler
		self.onBootstrapComplete = onBootstrapComplete
		self.supplementalProbePaths = supplementalProbePaths
		self.isPreferredDeviceReachable = isPreferredDeviceReachable
		networkReachable = reachability.currentState.isReachable
		applySessionActive(Self.hasPersistedDeviceSession(preferences: preferences) || sessionActive)
	}

	/// Re-reads persisted prefs / bookmarks and updates `sessionActive` (e.g. after cold launch).
	public func refreshSessionActive() {
		guard let preferences else { return }
		let active = Self.hasPersistedDeviceSession(preferences: preferences)
			|| !OCBookmarkManager.shared.bookmarks.isEmpty
		applySessionActive(active)
	}

	public func setNetworkReachable(_ reachable: Bool) {
		networkReachable = reachable
		publish()
	}

	public func setDeviceAccess(_ state: DeviceAccessState) {
		setDeviceAccess(state, allowDuringRAAuth: false)
	}

	private func setDeviceAccess(_ state: DeviceAccessState, allowDuringRAAuth: Bool) {
		guard sessionActive else { return }
		if awaitingRAAuthentication && !allowDuringRAAuth { return }
		if suppressConnectivitySnackbar,
		   !allowDuringRAAuth,
		   state == .connecting || state == .disconnected {
			return
		}
		guard deviceAccess != state else { return }
		deviceAccess = state
		publish()
	}

	public func reset() {
		pathRecoveryTask?.cancel()
		pathRecoveryTask = nil
		awaitingRAAuthentication = false
		suppressConnectivitySnackbar = false
		launchDetectionComplete = false
		sessionActive = false
		deviceAccess = .connected
		networkReachable = reachability?.currentState.isReachable ?? true
		lastErrorRecoveryAt = nil
		publish()
	}

	/// Starts a fresh device connectivity session (login or reconnect).
	public func beginSession() {
		let wasActive = sessionActive
		applySessionActive(true)
		if !wasActive {
			Task { await self.noteLaunchDetectionComplete() }
		}
	}

	private func applySessionActive(_ active: Bool) {
		let wasActive = sessionActive
		sessionActive = active
		if active && !wasActive {
			deviceAccess = .connected
			suppressConnectivitySnackbar = true
		}
		if !active {
			suppressConnectivitySnackbar = false
		}
		if active != wasActive || active {
			publish()
		}
		if active {
			Task { await self.finishBootstrapIfReady() }
		}
	}

	private func finishBootstrapIfReady() async {
		guard sessionActive, suppressConnectivitySnackbar, launchDetectionComplete else { return }
		suppressConnectivitySnackbar = false
		await validateConnectivityAfterBootstrap()
		await onBootstrapComplete?()
	}

	private func validateConnectivityAfterBootstrap() async {
		guard sessionActive, networkReachable, let preferences else {
			publish()
			return
		}

		let paths = await configuredProbePaths(preferences: preferences)
		guard !paths.isEmpty else {
			if await preferredDeviceIsReachable() {
				markDeviceConnected()
			}
			publish()
			return
		}

		let result = await probeConfiguredPaths(
			paths: paths,
			currentPathKey: preferences.currentConnectedDevice?.lastSuccessfulPathKey,
			localPathsAllowed: localPathsAllowed
		)

		await handleConfiguredProbeResult(result, localPathsAllowed: localPathsAllowed)
	}

	private func handleConfiguredProbeResult(
		_ result: PathConnectivityProbeResult,
		localPathsAllowed: Bool
	) async {
		switch result {
			case .currentPathReachable:
				markDeviceConnected()
			case .alternatePathReachable:
				await runPathRecovery(
					localPathsAllowed: localPathsAllowed,
					skipInitialProbe: true,
					silentWhenConnected: true
				)
			case .allUnreachable:
				await handleAllConfiguredPathsUnreachable(localPathsAllowed: localPathsAllowed)
		}
	}

	private func handleAllConfiguredPathsUnreachable(localPathsAllowed: Bool) async {
		if await preferredDeviceIsReachable() {
			markDeviceConnected()
			await runPathRecovery(
				localPathsAllowed: localPathsAllowed,
				skipInitialProbe: true,
				silentWhenConnected: true
			)
			return
		}
		await runPathRecovery(
			localPathsAllowed: localPathsAllowed,
			skipInitialProbe: true,
			localPathsFailed: true
		)
	}

	private func preferredDeviceIsReachable() async -> Bool {
		await isPreferredDeviceReachable?() == true
	}

	private static func hasPersistedDeviceSession(preferences: HCPreferences) -> Bool {
		preferences.currentConnectedDevice != nil || preferences.favoriteDeviceCN != nil
	}

	/// Periodic host-screen probe: current path first, then alternates.
	public func evaluateConfiguredPaths(localPathsAllowed: Bool) async {
		guard sessionActive, networkReachable, !awaitingRAAuthentication, isBootstrapComplete, let preferences else { return }

		let paths = await configuredProbePaths(preferences: preferences)
		guard !paths.isEmpty else {
			if await preferredDeviceIsReachable() {
				markDeviceConnected()
				await runPathRecovery(
					localPathsAllowed: localPathsAllowed,
					skipInitialProbe: true,
					silentWhenConnected: true
				)
			} else {
				await runPathRecovery(
					localPathsAllowed: localPathsAllowed,
					skipInitialProbe: true,
					localPathsFailed: true
				)
			}
			return
		}

		let result = await probeConfiguredPaths(
			paths: paths,
			currentPathKey: preferences.currentConnectedDevice?.lastSuccessfulPathKey,
			localPathsAllowed: localPathsAllowed
		)

		await handleConfiguredProbeResult(result, localPathsAllowed: localPathsAllowed)
	}

	/// User tapped Retry — full recovery including RA auth when required.
	public func retry() async {
		await runPathRecovery(localPathsAllowed: localPathsAllowed)
	}

	/// Transport / SDK errors — throttled full path recovery (same flow as Retry).
	public func triggerPathRecoveryFromError(localPathsAllowed: Bool) async {
		guard isBootstrapComplete else { return }
		let now = Date()
		if let last = lastErrorRecoveryAt,
		   now.timeIntervalSince(last) < errorRecoveryThrottleSeconds {
			return
		}
		lastErrorRecoveryAt = now
		Log.debug("[STX-RA]: Transport failure → coordinator path recovery")
		await runPathRecovery(localPathsAllowed: localPathsAllowed)
	}

	/// Full path recovery: optional fast probe → RA auth if needed → reload paths.
	public func runPathRecovery(
		localPathsAllowed: Bool,
		skipInitialProbe: Bool = false,
		localPathsFailed: Bool = false,
		silentWhenConnected: Bool = false
	) async {
		guard sessionActive, networkReachable else { return }
		if suppressConnectivitySnackbar && !silentWhenConnected { return }

		if let inFlight = pathRecoveryTask {
			await inFlight.value
			return
		}

		let task = Task { [self] in
			await self.performPathRecovery(
				localPathsAllowed: localPathsAllowed,
				skipInitialProbe: skipInitialProbe,
				localPathsFailed: localPathsFailed,
				silentWhenConnected: silentWhenConnected
			)
		}
		pathRecoveryTask = task
		await task.value
		pathRecoveryTask = nil
	}

	private func performPathRecovery(
		localPathsAllowed: Bool,
		skipInitialProbe: Bool,
		localPathsFailed: Bool,
		silentWhenConnected: Bool
	) async {
		guard sessionActive, networkReachable else { return }

		let suppressConnectingUI = silentWhenConnected && deviceAccess == .connected
		if !suppressConnectingUI {
			setDeviceAccess(.connecting)
		}

		var localProbeFailed = localPathsFailed
		if localProbeFailed, await preferredDeviceIsReachable() {
			localProbeFailed = false
		}

		if !skipInitialProbe, let preferences {
			let paths = await configuredProbePaths(preferences: preferences)
			if !paths.isEmpty {
				let result = await probeConfiguredPaths(
					paths: paths,
					currentPathKey: preferences.currentConnectedDevice?.lastSuccessfulPathKey,
					localPathsAllowed: localPathsAllowed,
					suppressConnectingUI: suppressConnectingUI
				)
				switch result {
					case .currentPathReachable:
						markDeviceConnected()
						return
					case .alternatePathReachable:
						await pathRecoveryHandler?(suppressConnectingUI)
						markDeviceConnected()
						return
					case .allUnreachable:
						localProbeFailed = true
				}
			}
		}

		// Run full discovery (mDNS, path reload) before RA — local may be available even
		// when saved WAN paths fail and the catalog has not been populated yet.
		await pathRecoveryHandler?(suppressConnectingUI)
		if await preferredDeviceIsReachable() {
			markDeviceConnected()
			return
		}
		if localPathsAllowed {
			localProbeFailed = true
		}

		if await requiresRAAuthentication(
			localPathsAllowed: localPathsAllowed,
			localProbeFailed: localProbeFailed
		) {
			guard let email = recoveryEmail() else {
				Log.debug("[STX-RA]: RA tokens missing but no email available for verification.")
				setDeviceAccess(.disconnected, allowDuringRAAuth: true)
				return
			}
			Log.debug("[STX-RA]: Requesting RA verification for \(email).")
			awaitingRAAuthentication = true
			defer { awaitingRAAuthentication = false }
			setDeviceAccess(.connecting, allowDuringRAAuth: true)
			let authenticated = await requestRAAuthentication(email: email)
			if !authenticated {
				setDeviceAccess(.disconnected, allowDuringRAAuth: true)
				return
			}
			await pathRecoveryHandler?(suppressConnectingUI)
			await finalizeDeviceAccessAfterRecovery(suppressConnectingUI: suppressConnectingUI)
			return
		}

		await finalizeDeviceAccessAfterRecovery(suppressConnectingUI: suppressConnectingUI)
	}

	private func needsRemoteAccessForRecovery(localPathsAllowed: Bool, localProbeFailed: Bool) -> Bool {
		guard let preferences else { return localProbeFailed || !localPathsAllowed }
		let paths = Self.pathsForConnectedDevice(preferences: preferences)
		if paths.isEmpty { return true }
		if !localPathsAllowed { return true }
		return localProbeFailed
	}

	private func recoveryEmail() -> String? {
		if let email = preferences?.favoriteEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !email.isEmpty {
			return email
		}
		if let userName = OCBookmarkManager.shared.bookmarks.first?.userName?
			.trimmingCharacters(in: .whitespacesAndNewlines),
		   !userName.isEmpty,
		   userName.contains("@") {
			return userName
		}
		return nil
	}

	private func probeConfiguredPaths(
		paths: [RemoteDevice.Path],
		currentPathKey: String?,
		localPathsAllowed: Bool,
		suppressConnectingUI: Bool = false
	) async -> PathConnectivityProbeResult {
		let coordinator = self
		return await pathProber.probeConnectivityCurrentFirst(
			paths: paths,
			currentPathKey: currentPathKey,
			localPathsAllowed: localPathsAllowed
		) {
			guard !suppressConnectingUI else { return }
			await coordinator.setDeviceAccess(.connecting)
		}
	}

	private func requiresRAAuthentication(localPathsAllowed: Bool, localProbeFailed: Bool) async -> Bool {
		guard let remoteAccessService else { return false }
		guard await remoteAccessService.hasValidTokens() == false else { return false }
		return needsRemoteAccessForRecovery(
			localPathsAllowed: localPathsAllowed,
			localProbeFailed: localProbeFailed
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

	private var localPathsAllowed: Bool {
		reachability?.currentState.allowsLocalPaths ?? true
	}

	public func confirmDeviceReachable() {
		markDeviceConnected()
	}

	/// Called when the active device base URL changes (path switch). Dismisses a stale
	/// "finding network" banner even when recovery finished outside `performPathRecovery`.
	public func noteActivePathAvailable() {
		guard sessionActive, networkReachable else { return }
		markDeviceConnected(allowDuringRAAuth: true)
	}

	private func markDeviceConnected(allowDuringRAAuth: Bool = false) {
		guard sessionActive else { return }
		if awaitingRAAuthentication && !allowDuringRAAuth { return }
		deviceAccess = .connected
		publish()
	}

	/// Ensures recovery never leaves the UI stuck in `.connecting`.
	private func finalizeDeviceAccessAfterRecovery(suppressConnectingUI: Bool) async {
		guard deviceAccess == .connecting else { return }
		if await preferredDeviceIsReachable() {
			markDeviceConnected(allowDuringRAAuth: true)
			return
		}
		if !suppressConnectingUI {
			setDeviceAccess(.disconnected, allowDuringRAAuth: true)
		}
	}

	private func publish() {
		let sdkConnected = sessionActive && networkReachable && deviceAccess == .connected
		SDKDeviceAvailabilityGate.shared.setDeviceConnected(sdkConnected)

		guard let toastMonitor else { return }
		let kind: NetworkAvailabilityToastKind?
		if !networkReachable {
			kind = .noInternet
		} else if !sessionActive {
			kind = nil
		} else if suppressConnectivitySnackbar {
			kind = nil
		} else {
			switch deviceAccess {
				case .connected:     kind = nil
				case .connecting:    kind = .findingNetwork
				case .disconnected:  kind = .connectionLost
			}
		}

		toastPublishGeneration &+= 1
		let generation = toastPublishGeneration
		Task {
			guard generation == self.toastPublishGeneration else { return }
			await toastMonitor.setVisibility(kind)
		}
	}

	private static func pathsForConnectedDevice(preferences: HCPreferences) -> [RemoteDevice.Path] {
		guard let saved = preferences.currentConnectedDevice else { return [] }
		return saved.paths.map { $0.asRemotePath() }.ordered()
	}

	private func configuredProbePaths(preferences: HCPreferences) async -> [RemoteDevice.Path] {
		var paths = Self.pathsForConnectedDevice(preferences: preferences)
		if let supplemental = await supplementalProbePaths?() {
			paths = Self.merging(paths, with: supplemental)
		}
		return paths
	}

	private static func merging(
		_ paths: [RemoteDevice.Path],
		with supplemental: [RemoteDevice.Path]
	) -> [RemoteDevice.Path] {
		var seen = Set(paths.map(\.key))
		var merged = paths
		for path in supplemental where seen.insert(path.key).inserted {
			merged.append(path)
		}
		return merged.ordered()
	}
}
