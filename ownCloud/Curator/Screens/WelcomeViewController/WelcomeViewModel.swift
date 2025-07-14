protocol WelcomeViewModelEventHandler: AnyObject {
	func handle(_ event: WelcomeViewModel.Event)
}

final class WelcomeViewModel {
	enum Event {
		case startSetupTap
		case settingsTap
	}

	private let eventHandler: WelcomeViewModelEventHandler

	init(eventHandler: WelcomeViewModelEventHandler) {
		self.eventHandler = eventHandler
	}

	deinit {
		print("4242: WelcomeViewModel died")
	}

	func didTapStartSetup() {
		eventHandler.handle(.startSetupTap)
	}

	func didTapSettings() {
		eventHandler.handle(.settingsTap)
	}
}
