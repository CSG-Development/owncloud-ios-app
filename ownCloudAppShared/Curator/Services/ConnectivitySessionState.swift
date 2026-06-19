import Foundation
import ownCloudSDK

/// Input events for the connectivity session state machine.
enum ConnectivitySessionEvent: Equatable {
	case reset(networkReachable: Bool)
	case setNetworkReachable(Bool)
	case activateSession
	case deactivateSession
	case applyDeviceAccess(DeviceAccessState)
	case beginRemoteAuthentication
	case endRemoteAuthentication(DeviceAccessState)
}

/// Effects produced by a session transition.
struct ConnectivitySessionTransition: Equatable {
	var connectivityChanged = false
	var deviceAccessChanged = false
}

/// Pure session state machine for connectivity phase, network, and device access.
struct ConnectivitySessionState: Equatable {
	var connectivity: ConnectivityState = .loggedOut(networkReachable: true)

	var networkReachable: Bool { connectivity.networkReachable }
	var deviceAccess: DeviceAccessState { connectivity.deviceAccess }
	var isLoggedOut: Bool { connectivity.isLoggedOut }
	var isActive: Bool { connectivity.isActive }
	var isAwaitingRemoteAuthentication: Bool { connectivity.isAwaitingRemoteAuthentication }

	mutating func handle(_ event: ConnectivitySessionEvent) -> ConnectivitySessionTransition {
		switch event {
			case .reset(let reachable):
				return handleReset(networkReachable: reachable)
			case .setNetworkReachable(let reachable):
				return handleSetNetworkReachable(reachable)
			case .activateSession:
				return handleActivateSession()
			case .deactivateSession:
				return handleDeactivateSession()
			case .applyDeviceAccess(let state):
				return handleApplyDeviceAccess(state)
			case .beginRemoteAuthentication:
				return handleBeginRemoteAuthentication()
			case .endRemoteAuthentication(let device):
				return handleEndRemoteAuthentication(device: device)
		}
	}

	func checkRecoveryEligibility() -> ConnectivityRecoveryEligibility {
		guard !isLoggedOut else { return .ineligible("no active session") }
		guard networkReachable else { return .ineligible("network unreachable") }
		return .eligible
	}

	func checkPeriodicProbeEligibility(recoveryInFlight: Bool) -> ConnectivityRecoveryEligibility {
		if recoveryInFlight { return .ineligible("recovery in flight") }
		guard isActive else { return .ineligible("phase=\(connectivity)") }
		guard networkReachable else { return .ineligible("network unreachable") }
		guard !isAwaitingRemoteAuthentication else { return .ineligible("awaiting RA auth") }
		return .eligible
	}

	static func hasPersistedDeviceSession(preferences: HCPreferences) -> Bool {
		preferences.currentConnectedDevice != nil || preferences.favoriteDeviceCN != nil
	}

	// MARK: - Transition table

	private mutating func handleReset(networkReachable: Bool) -> ConnectivitySessionTransition {
		let before = connectivity
		connectivity = .loggedOut(networkReachable: networkReachable)
		ConnectivityEventLog.stateTransition(from: before, to: connectivity, reason: "reset")
		return ConnectivitySessionTransition(connectivityChanged: before != connectivity)
	}

	private mutating func handleSetNetworkReachable(_ reachable: Bool) -> ConnectivitySessionTransition {
		guard networkReachable != reachable else { return ConnectivitySessionTransition() }
		let before = connectivity
		updateNetworkReachable(reachable)
		return ConnectivitySessionTransition(connectivityChanged: before != connectivity)
	}

	private mutating func handleActivateSession() -> ConnectivitySessionTransition {
		guard isLoggedOut else { return ConnectivitySessionTransition() }
		let before = connectivity
		connectivity = .active(networkReachable: networkReachable, device: .connected)
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

	private mutating func handleApplyDeviceAccess(
		_ state: DeviceAccessState
	) -> ConnectivitySessionTransition {
		guard !isLoggedOut else {
			ConnectivityEventLog.deviceAccessSuppressed(state, reason: "logged out")
			return ConnectivitySessionTransition()
		}
		guard deviceAccess != state else { return ConnectivitySessionTransition() }
		let previous = deviceAccess
		updateDevice(state)
		ConnectivityEventLog.deviceAccess(from: previous, to: state)
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

	private mutating func updateNetworkReachable(_ reachable: Bool) {
		switch connectivity {
			case .loggedOut:
				connectivity = .loggedOut(networkReachable: reachable)
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
			case .active(let reachable, _):
				connectivity = .active(networkReachable: reachable, device: state)
			case .authenticatingRemoteAccess(let reachable, _):
				connectivity = .authenticatingRemoteAccess(networkReachable: reachable, device: state)
		}
	}
}
