import Foundation
import ownCloudSDK

public enum DeviceAccessState: Sendable, Equatable, CustomStringConvertible {
	case connected
	case connecting
	case disconnected

	public var description: String {
		switch self {
			case .connected:     return "connected"
			case .connecting:    return "connecting"
			case .disconnected:  return "disconnected"
		}
	}
}

/// Unified connectivity state — session phase, network, and device access in one model.
public enum ConnectivityState: Equatable, Sendable, CustomStringConvertible {
	case loggedOut(networkReachable: Bool)
	case active(networkReachable: Bool, device: DeviceAccessState)
	case authenticatingRemoteAccess(networkReachable: Bool, device: DeviceAccessState)

	public var description: String {
		switch self {
			case .loggedOut:
				return "loggedOut"
			case .active:
				return "active"
			case .authenticatingRemoteAccess:
				return "authenticatingRemoteAccess"
		}
	}

	public var networkReachable: Bool {
		switch self {
			case .loggedOut(let reachable):                    return reachable
			case .active(let reachable, _):                     return reachable
			case .authenticatingRemoteAccess(let reachable, _): return reachable
		}
	}

	public var deviceAccess: DeviceAccessState {
		switch self {
			case .loggedOut:                                    return .connected
			case .active(_, let device):                         return device
			case .authenticatingRemoteAccess(_, let device):     return device
		}
	}

	public var isLoggedOut: Bool {
		if case .loggedOut = self { return true }
		return false
	}

	public var isActive: Bool {
		if case .active = self { return true }
		return false
	}

	public var isAwaitingRemoteAuthentication: Bool {
		if case .authenticatingRemoteAccess = self { return true }
		return false
	}
}

/// Why a connectivity evaluation was requested. Logging / diagnostics only.
public enum ConnectivityEvaluateReason: String, Sendable {
	case networkChanged
	case foreground
	case periodic
	case retry
	case transportError
	case discovery
	case login
	case sessionStart
}

enum ConnectivityRecoveryEligibility: Equatable {
	case eligible
	case ineligible(String)
}
