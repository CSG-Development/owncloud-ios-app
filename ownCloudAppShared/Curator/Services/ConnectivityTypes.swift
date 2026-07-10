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

/// Controls when the recovery runner may reveal the "Finding network" snackbar mid-evaluation.
/// User Retry shows the banner immediately in `ConnectivityStateCoordinator.retry()` instead.
enum FindingNetworkBannerPolicy: Equatable, Sendable {
	/// Do not reveal the banner from the runner (cold start, latched background checks, Retry).
	case never
	/// Reveal the banner once the current path is confirmed unreachable, then keep it for discovery.
	case whenUnreachable
}

/// Per-evaluation options derived from the trigger reason and current banner latch state.
struct ConnectivityEvaluationContext: Equatable, Sendable {
	var bannerPolicy: FindingNetworkBannerPolicy
	/// Keep the SDK online while probing when the device was connected at evaluation start.
	var retainSDKOnActiveConnection: Bool
	/// Force a full server-address catalog refresh before probing (Retry).
	var forceCatalogReload: Bool

	static func make(
		for reason: ConnectivityEvaluateReason,
		deviceAccess: DeviceAccessState,
		connectionLostLatched: Bool,
		hasCompletedInitialEvaluation: Bool
	) -> ConnectivityEvaluationContext {
		let silentWhileLatchedOrColdStart = connectionLostLatched || !hasCompletedInitialEvaluation
		let bannerPolicy: FindingNetworkBannerPolicy
		switch reason {
			case .retry, .discovery, .sessionStart, .login:
				// `.retry` — banner is shown by `retry()` → `beginRetrySearch()` before evaluate runs.
				bannerPolicy = .never
			case .transportError, .networkChanged:
				bannerPolicy = connectionLostLatched ? .never : .whenUnreachable
			case .periodic, .foreground:
				bannerPolicy = silentWhileLatchedOrColdStart ? .never : .whenUnreachable
		}
		return ConnectivityEvaluationContext(
			bannerPolicy: bannerPolicy,
			retainSDKOnActiveConnection: deviceAccess == .connected,
			forceCatalogReload: reason == .retry
		)
	}
}

/// UI presentation flags for the connectivity snackbar and SDK gate latch.
struct ConnectivityBannerPresentation: Equatable, Sendable {
	var findingNetworkVisible = false
	var connectionLostLatched = false
	var sdkConnectionRetained = false

	mutating func reset() {
		findingNetworkVisible = false
		connectionLostLatched = false
		sdkConnectionRetained = false
	}

	mutating func clearTransientOnNetworkDown() {
		findingNetworkVisible = false
		sdkConnectionRetained = false
	}

	/// User tapped Retry: show "Finding network" immediately for the full search duration.
	mutating func beginRetrySearch() {
		connectionLostLatched = false
		findingNetworkVisible = true
	}

	mutating func showFindingNetwork() -> Bool {
		guard !findingNetworkVisible else { return false }
		findingNetworkVisible = true
		return true
	}

	mutating func finishConnected() {
		findingNetworkVisible = false
		connectionLostLatched = false
		sdkConnectionRetained = false
	}

	mutating func finishDisconnected() {
		findingNetworkVisible = false
		connectionLostLatched = true
		sdkConnectionRetained = false
	}
}
