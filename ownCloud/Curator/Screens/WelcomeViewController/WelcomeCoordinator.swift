import ownCloudAppShared
import ownCloudApp

protocol WelcomeCoordinatorEventHandler: AnyObject {
	func handle(_ event: WelcomeCoordinator.Event)
}

final class WelcomeCoordinator {
	enum Event {
		case startSetupTap
		case settingsTap
	}

	private weak var eventHandler: WelcomeCoordinatorEventHandler?

	init(eventHandler: WelcomeCoordinatorEventHandler) {
		self.eventHandler = eventHandler
	}

	deinit {
		print("4242: WelcomeCoordinator died")
	}

	func makeInitial() -> WelcomeViewController {
		let vm = WelcomeViewModel(eventHandler: self)
		let vc = WelcomeViewController(viewModel: vm)
		return vc
	}
}

extension WelcomeCoordinator: WelcomeViewModelEventHandler {
	func handle(_ event: WelcomeViewModel.Event) {
		switch event {
			case .startSetupTap:
				eventHandler?.handle(.startSetupTap)
			case .settingsTap:
				eventHandler?.handle(.settingsTap)
		}
	}
}
