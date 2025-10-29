protocol OldLoginCoordinatorEventHandler: AnyObject {
	func handle(_ event: OldLoginCoordinator.Event)
}

final class OldLoginCoordinator {
	private weak var eventHandler: OldLoginCoordinatorEventHandler?
	enum Event {
		case loginTap
		case resetPasswordTap
		case settingsTap
	}

	init(eventHandler: OldLoginCoordinatorEventHandler) {
		self.eventHandler = eventHandler
	}

	func makeInitial() -> OldLoginViewController {
		let vm = OldLoginViewModel(eventHandler: self)
		let vc = OldLoginViewController(viewModel: vm)
		return vc
	}
}

extension OldLoginCoordinator: OldLoginViewModelEventHandler {
	func handle(_ event: OldLoginViewModel.Event) {
		switch event {
			case .loginTap:
				eventHandler?.handle(.loginTap)
			case .resetPasswordTap:
				eventHandler?.handle(.resetPasswordTap)
			case .settingsTap:
				eventHandler?.handle(.settingsTap)
		}
	}
}
