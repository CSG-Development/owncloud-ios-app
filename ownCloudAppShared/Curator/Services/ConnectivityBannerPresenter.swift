import Foundation

/// Maps connectivity state to the SDK gate and host-screen snackbar.
struct ConnectivityBannerPresenter {
	let snackbarDrivingEnabled: Bool
	let connectivity: ConnectivityState
	let pipelineReloading: Bool

	var sdkConnected: Bool {
		!connectivity.isLoggedOut && connectivity.networkReachable && connectivity.deviceAccess == .connected
	}

	func bannerKind() -> (kind: NetworkAvailabilityToastKind?, suppressReason: String?) {
		guard snackbarDrivingEnabled else { return (nil, "snackbar disabled") }
		if connectivity.isLoggedOut {
			return (nil, "no session")
		}
		if !connectivity.networkReachable {
			return (.noInternet, nil)
		}
		if pipelineReloading || connectivity.deviceAccess == .connecting {
			return (.findingNetwork, nil)
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
