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

/// Facts reported by `DeviceReachabilityService` after catalog reload or sync.
public struct CatalogReachabilitySnapshot: Sendable, Equatable {
	public let hasDeviceCN: Bool
	public let isReachable: Bool
	/// A non-local path is queued for the SDK even though nothing is verified yet.
	public let hasAlternateNonLocalPath: Bool

	public init(hasDeviceCN: Bool, isReachable: Bool, hasAlternateNonLocalPath: Bool = false) {
		self.hasDeviceCN = hasDeviceCN
		self.isReachable = isReachable
		self.hasAlternateNonLocalPath = hasAlternateNonLocalPath
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

enum ConnectivityAccessPolicy: Equatable, CustomStringConvertible {
	case normal
	case duringRAAuth
	case catalogSync
	case pathEvidence
	case pathAvailable
	case recoveryFinalize

	var description: String {
		switch self {
			case .normal:           return "normal"
			case .duringRAAuth:     return "duringRAAuth"
			case .catalogSync:      return "catalogSync"
			case .pathEvidence:     return "pathEvidence"
			case .pathAvailable:    return "pathAvailable"
			case .recoveryFinalize: return "recoveryFinalize"
		}
	}
}

enum ConnectivityRecoveryEligibility: Equatable {
	case eligible
	case ineligible(String)
}

struct ConnectivityRecoveryRequest: Equatable {
	var localPathsAllowed: Bool
	var skipInitialProbe: Bool
	var localPathsFailed: Bool
	var fromTransportError: Bool
	/// Probe found a reachable path other than the current one — catalog reload must run to switch.
	var alternatePathReachable: Bool

	/// Merges a coalesced recovery with a new request while an earlier recovery is in flight.
	///
	/// - `localPathsAllowed`: always the **incoming** value (latest network interface snapshot).
	/// - `skipInitialProbe`: AND — stricter wins.
	/// - `localPathsFailed` / `fromTransportError` / `alternatePathReachable`: OR — preserved if any set.
	static func merge(_ existing: Self?, with incoming: Self) -> Self {
		guard let existing else { return incoming }
		return Self(
			localPathsAllowed: incoming.localPathsAllowed,
			skipInitialProbe: existing.skipInitialProbe && incoming.skipInitialProbe,
			localPathsFailed: existing.localPathsFailed || incoming.localPathsFailed,
			fromTransportError: existing.fromTransportError || incoming.fromTransportError,
			alternatePathReachable: existing.alternatePathReachable || incoming.alternatePathReachable
		)
	}
}

enum ConnectivityProbeResultLabel {
	static func label(_ result: PathConnectivityProbeResult) -> String {
		switch result {
			case .currentPathReachable:   return "currentReachable"
			case .alternatePathReachable: return "alternateReachable"
			case .allUnreachable:         return "allUnreachable"
		}
	}
}
