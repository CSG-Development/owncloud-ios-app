
protocol LoginCoordinatorEventHandler: AnyObject {
	func handle(_ event: LoginCoordinator.Event)
}

final class LoginCoordinator {
	private weak var eventHandler: LoginCoordinatorEventHandler?
	enum Event {
		case loginTap
		case moreInfoTap
		case settingsTap
	}

	init(eventHandler: LoginCoordinatorEventHandler) {
		self.eventHandler = eventHandler
	}

	deinit {
		print("4242: LoginCoordinator died")
	}

	func makeInitial() -> LoginViewController {		
		let vm = LoginViewModel(eventHandler: self)
		let vc = LoginViewController(viewModel: vm)
		return vc
	}
}

extension LoginCoordinator: LoginViewModelEventHandler {
	func handle(_ event: LoginViewModel.Event) {
		switch event {
			case .loginTap:
				eventHandler?.handle(.loginTap)
			case .moreInfoTap:
				eventHandler?.handle(.moreInfoTap)
			case .settingsTap:
				eventHandler?.handle(.settingsTap)
		}
	}
}
