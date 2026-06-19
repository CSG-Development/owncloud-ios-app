import Foundation
import ownCloudSDK

/// Maps connectivity state to the SDK gate and host-screen snackbar.
struct ConnectivityBannerPresenter {
	let snackbarDrivingEnabled: Bool
	let connectivity: ConnectivityState
	let pipelineReloading: Bool
	let sdkCoreConnectionStatus: OCCoreConnectionStatus?

	var sdkConnected: Bool {
		guard !connectivity.isLoggedOut,
		      connectivity.isActive,
		      connectivity.networkReachable,
		      connectivity.deviceAccess == .connected
		else { return false }
		return true
	}

	func bannerKind() -> (kind: NetworkAvailabilityToastKind?, suppressReason: String?) {
		guard snackbarDrivingEnabled else { return (nil, "snackbar disabled") }
		if connectivity.isLoggedOut {
			return (nil, "no session")
		}
		if !connectivity.networkReachable {
			return (.noInternet, nil)
		}
		if connectivity.deviceAccess == .disconnected {
			return (.connectionLost, nil)
		}
		if shouldShowPipelineFindingNetwork {
			return (.findingNetwork, nil)
		}
		switch connectivity.deviceAccess {
			case .connected:     return (nil, nil)
			case .connecting:    return (.findingNetwork, nil)
			case .disconnected:  return (.connectionLost, nil)
		}
	}

	/// Only surface reload UI while the device or SDK is still coming online — not after
	/// both are steady (avoids stale `pipelineReloadDepth` keeping the banner up).
	private var shouldShowPipelineFindingNetwork: Bool {
		guard pipelineReloading else { return false }
		if connectivity.deviceAccess == .connecting { return true }
		return isAwaitingSDKOnline
	}

	/// Snackbar only — wait for `OCCore` to report `.online` before hiding.
	/// The SDK availability gate must not use this: forcing reachable offline while
	/// the core is still connecting prevents it from ever reaching `.online`.
	private var isAwaitingSDKOnline: Bool {
		guard connectivity.isActive,
		      connectivity.deviceAccess == .connected,
		      sdkCoreConnectionStatus != nil
		else { return false }
		return sdkCoreConnectionStatus != .online
	}

	static func coreStatusLabel(_ status: OCCoreConnectionStatus?) -> String {
		guard let status else { return "none" }
		switch status {
			case .offline:      return "offline"
			case .unavailable:   return "unavailable"
			case .connecting:    return "connecting"
			case .online:        return "online"
			@unknown default:    return "unknown(\(status.rawValue))"
		}
	}

	static func bannerLabel(_ kind: NetworkAvailabilityToastKind?) -> String {
		switch kind {
			case nil:                 return "hidden"
			case .findingNetwork:      return "findingNetwork"
			case .noInternet:          return "noInternet"
			case .connectionLost:      return "connectionLost"
		}
	}
}
