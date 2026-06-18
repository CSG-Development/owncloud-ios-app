import Foundation
import ownCloudSDK

/// Input events for the connectivity session state machine.
enum ConnectivitySessionEvent: Equatable {
	case reset(networkReachable: Bool)
	case setNetworkReachable(Bool)
	case activateSession(ConnectivityBootstrapWait)
	case deactivateSession
	case finishBootstrap
	case applyDeviceAccess(DeviceAccessState, ConnectivityAccessPolicy)
	case beginRemoteAuthentication
	case endRemoteAuthentication(DeviceAccessState)
	case markLaunchDetectionComplete
}

/// Effects produced by a session transition.
struct ConnectivitySessionTransition: Equatable {
	var connectivityChanged = false
	var deviceAccessChanged = false
	var launchDetectionMarkedComplete = false
}

/// Pure session state machine for connectivity phase, network, and device access.
struct ConnectivitySessionState: Equatable {
	var connectivity: ConnectivityState = .loggedOut(networkReachable: true)
	var coldLaunchDetectionComplete = false

	var networkReachable: Bool { connectivity.networkReachable }
	var deviceAccess: DeviceAccessState { connectivity.deviceAccess }
	var isLoggedOut: Bool { connectivity.isLoggedOut }
	var isBootstrapping: Bool { connectivity.isBootstrapping }
	var isActive: Bool { connectivity.isActive }
	var isAwaitingRemoteAuthentication: Bool { connectivity.isAwaitingRemoteAuthentication }

	var shouldCompleteLaunchBootstrap: Bool {
		if case .bootstrapping(.launchDetection, _, _) = connectivity, coldLaunchDetectionComplete {
			return true
		}
		return false
	}

	var shouldCompleteLoginBootstrap: Bool {
		if case .bootstrapping(.loginCatalog, _, _) = connectivity { return true }
		return false
	}

	mutating func handle(_ event: ConnectivitySessionEvent) -> ConnectivitySessionTransition {
		switch event {
			case .reset(let reachable):
				return handleReset(networkReachable: reachable)
			case .setNetworkReachable(let reachable):
				return handleSetNetworkReachable(reachable)
			case .activateSession(let bootstrap):
				return handleActivateSession(bootstrap: bootstrap)
			case .deactivateSession:
				return handleDeactivateSession()
			case .finishBootstrap:
				return handleFinishBootstrap()
			case .applyDeviceAccess(let state, let policy):
				return handleApplyDeviceAccess(state, policy: policy)
			case .beginRemoteAuthentication:
				return handleBeginRemoteAuthentication()
			case .endRemoteAuthentication(let device):
				return handleEndRemoteAuthentication(device: device)
			case .markLaunchDetectionComplete:
				return handleMarkLaunchDetectionComplete()
		}
	}

	func checkRecoveryEligibility() -> ConnectivityRecoveryEligibility {
		guard !isLoggedOut else { return .ineligible("no active session") }
		guard networkReachable else { return .ineligible("network unreachable") }
		if isBootstrapping {
			return .ineligible("bootstrap in progress")
		}
		return .eligible
	}

	func checkPeriodicProbeEligibility(recoveryInFlight: Bool) -> ConnectivityRecoveryEligibility {
		if recoveryInFlight { return .ineligible("recovery in flight") }
		guard isActive else { return .ineligible("phase=\(connectivity)") }
		guard networkReachable else { return .ineligible("network unreachable") }
		guard !isAwaitingRemoteAuthentication else { return .ineligible("awaiting RA auth") }
		return .eligible
	}

	func checkPostBootstrapProbeEligibility() -> ConnectivityRecoveryEligibility {
		guard isActive, networkReachable else { return .ineligible("not active or network down") }
		return .eligible
	}

	static func hasPersistedDeviceSession(preferences: HCPreferences) -> Bool {
		preferences.currentConnectedDevice != nil || preferences.favoriteDeviceCN != nil
	}

	// MARK: - Transition table

	private mutating func handleReset(networkReachable: Bool) -> ConnectivitySessionTransition {
		let before = connectivity
		connectivity = .loggedOut(networkReachable: networkReachable)
		coldLaunchDetectionComplete = false
		ConnectivityEventLog.stateTransition(from: before, to: connectivity, reason: "reset")
		return ConnectivitySessionTransition(connectivityChanged: before != connectivity)
	}

	private mutating func handleSetNetworkReachable(_ reachable: Bool) -> ConnectivitySessionTransition {
		guard networkReachable != reachable else { return ConnectivitySessionTransition() }
		let before = connectivity
		updateNetworkReachable(reachable)
		return ConnectivitySessionTransition(connectivityChanged: before != connectivity)
	}

	private mutating func handleActivateSession(bootstrap: ConnectivityBootstrapWait) -> ConnectivitySessionTransition {
		guard isLoggedOut else { return ConnectivitySessionTransition() }
		let before = connectivity
		connectivity = .bootstrapping(
			wait: bootstrap,
			networkReachable: networkReachable,
			device: .connected
		)
		ConnectivityEventLog.stateTransition(from: before, to: connectivity, reason: "activateSession")
		return ConnectivitySessionTransition(connectivityChanged: true)
	}

	private mutating func handleDeactivateSession() -> ConnectivitySessionTransition {
		guard !isLoggedOut else { return ConnectivitySessionTransition() }
		let before = connectivity
		connectivity = .loggedOut(networkReachable: networkReachable)
		ConnectivityEventLog.stateTransition(from: before, to: connectivity, reason: "deactivateSession")
		return ConnectivitySessionTransition(connectivityChanged: true)
	}

	private mutating func handleFinishBootstrap() -> ConnectivitySessionTransition {
		guard isBootstrapping else { return ConnectivitySessionTransition() }
		let before = connectivity
		connectivity = .active(networkReachable: networkReachable, device: deviceAccess)
		ConnectivityEventLog.stateTransition(from: before, to: connectivity, reason: "finishBootstrap")
		return ConnectivitySessionTransition(connectivityChanged: true)
	}

	private mutating func handleApplyDeviceAccess(
		_ state: DeviceAccessState,
		policy: ConnectivityAccessPolicy
	) -> ConnectivitySessionTransition {
		guard !isLoggedOut else {
			ConnectivityEventLog.deviceAccessSuppressed(state, policy: policy, reason: "logged out")
			return ConnectivitySessionTransition()
		}
		if shouldSuppressDeviceAccess(state, policy: policy) {
			ConnectivityEventLog.deviceAccessSuppressed(state, policy: policy, reason: "policy")
			return ConnectivitySessionTransition()
		}
		guard deviceAccess != state else { return ConnectivitySessionTransition() }
		let previous = deviceAccess
		updateDevice(state)
		ConnectivityEventLog.deviceAccess(from: previous, to: state, policy: policy)
		return ConnectivitySessionTransition(connectivityChanged: true, deviceAccessChanged: true)
	}

	private mutating func handleBeginRemoteAuthentication() -> ConnectivitySessionTransition {
		guard case .active = connectivity else { return ConnectivitySessionTransition() }
		let before = connectivity
		connectivity = .authenticatingRemoteAccess(
			networkReachable: networkReachable,
			device: .connecting
		)
		ConnectivityEventLog.stateTransition(from: before, to: connectivity, reason: "beginRA")
		return ConnectivitySessionTransition(connectivityChanged: true, deviceAccessChanged: true)
	}

	private mutating func handleEndRemoteAuthentication(device: DeviceAccessState) -> ConnectivitySessionTransition {
		guard isAwaitingRemoteAuthentication else { return ConnectivitySessionTransition() }
		let before = connectivity
		connectivity = .active(networkReachable: networkReachable, device: device)
		ConnectivityEventLog.stateTransition(from: before, to: connectivity, reason: "endRA")
		return ConnectivitySessionTransition(
			connectivityChanged: true,
			deviceAccessChanged: before.deviceAccess != device
		)
	}

	private mutating func handleMarkLaunchDetectionComplete() -> ConnectivitySessionTransition {
		guard !coldLaunchDetectionComplete else { return ConnectivitySessionTransition() }
		coldLaunchDetectionComplete = true
		ConnectivityEventLog.log("launch detection complete")
		return ConnectivitySessionTransition(launchDetectionMarkedComplete: true)
	}

	private func shouldSuppressDeviceAccess(_ state: DeviceAccessState, policy: ConnectivityAccessPolicy) -> Bool {
		switch policy {
			case .duringRAAuth, .recoveryFinalize, .pathAvailable:
				return false
			case .pathEvidence:
				return isAwaitingRemoteAuthentication
			case .normal, .catalogSync:
				return isAwaitingRemoteAuthentication
		}
	}

	private mutating func updateNetworkReachable(_ reachable: Bool) {
		switch connectivity {
			case .loggedOut:
				connectivity = .loggedOut(networkReachable: reachable)
			case .bootstrapping(let wait, _, let device):
				connectivity = .bootstrapping(wait: wait, networkReachable: reachable, device: device)
			case .active(_, let device):
				connectivity = .active(networkReachable: reachable, device: device)
			case .authenticatingRemoteAccess(_, let device):
				connectivity = .authenticatingRemoteAccess(networkReachable: reachable, device: device)
		}
	}

	private mutating func updateDevice(_ state: DeviceAccessState) {
		switch connectivity {
			case .loggedOut(let reachable):
				connectivity = .loggedOut(networkReachable: reachable)
			case .bootstrapping(let wait, let reachable, _):
				connectivity = .bootstrapping(wait: wait, networkReachable: reachable, device: state)
			case .active(let reachable, _):
				connectivity = .active(networkReachable: reachable, device: state)
			case .authenticatingRemoteAccess(let reachable, _):
				connectivity = .authenticatingRemoteAccess(networkReachable: reachable, device: state)
		}
	}
}
