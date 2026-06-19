import Foundation
import ownCloudSDK

/// Maps connectivity state to the SDK gate and host-screen snackbar.
///
/// The banner is a pure function of the session: it never derives state from the SDK core
/// status or pipeline-reload depth. `ConnectivityStateCoordinator` is the single writer of
/// `deviceAccess`, so this type only has to translate three values into a banner kind.
struct ConnectivityBannerPresenter {
	let snackbarDrivingEnabled: Bool
	let connectivity: ConnectivityState

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
		switch connectivity.deviceAccess {
			case .connected:     return (nil, nil)
			case .connecting:    return (.findingNetwork, nil)
			case .disconnected:  return (.connectionLost, nil)
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
