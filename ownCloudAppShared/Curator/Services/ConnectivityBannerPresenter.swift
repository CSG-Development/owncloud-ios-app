import Foundation
import ownCloudSDK

/// Maps connectivity state to the SDK gate and host-screen snackbar.
///
/// Banner visibility is driven by explicit presentation flags (`findingNetworkBannerVisible`,
/// `connectionLostLatched`) in addition to session device access, so background probes and
/// cold-start discovery can run without flashing "Finding network" or disabling the SDK.
struct ConnectivityBannerPresenter {
	let snackbarDrivingEnabled: Bool
	let connectivity: ConnectivityState
	let findingNetworkBannerVisible: Bool
	let connectionLostLatched: Bool
	let sdkConnectionRetained: Bool

	var sdkConnected: Bool {
		guard !connectivity.isLoggedOut,
		      connectivity.isActive,
		      connectivity.networkReachable
		else { return false }
		if sdkConnectionRetained { return true }
		return connectivity.deviceAccess == .connected
	}

	func bannerKind() -> (kind: NetworkAvailabilityToastKind?, suppressReason: String?) {
		guard snackbarDrivingEnabled else { return (nil, "snackbar disabled") }
		if connectivity.isLoggedOut {
			return (nil, "no session")
		}
		if !connectivity.networkReachable {
			return (.noInternet, nil)
		}
		if findingNetworkBannerVisible {
			return (.findingNetwork, nil)
		}
		if connectionLostLatched || connectivity.deviceAccess == .disconnected {
			return (.connectionLost, nil)
		}
		return (nil, nil)
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
