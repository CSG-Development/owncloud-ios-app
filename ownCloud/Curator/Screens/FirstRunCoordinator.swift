import ownCloudAppShared
import ownCloudApp

final class FirstRunCoordinator {
	private weak var navigationController: UINavigationController?
	private weak var rootVC: AppRootViewController?
	private var selfHandle: AnyObject?

	init(rootVC: AppRootViewController?) {
		self.rootVC = rootVC
	}

	deinit {
		print("4242: FirstRunCoordinator died")
	}

	func makeInitial() -> ThemeNavigationController {
		let vc = WelcomeCoordinator(eventHandler: self).makeInitial()
		let nc = ThemeNavigationController(rootViewController: vc)
		nc.setNavigationBarHidden(true, animated: false)
		self.navigationController = nc
		self.selfHandle = self
		return nc
	}

	func openSettings() {
		let navigationViewController = ThemeNavigationController(rootViewController: SettingsViewController())
		navigationViewController.modalPresentationStyle = .fullScreen
		navigationController?.present(navigationViewController, animated: true)
	}
}

extension FirstRunCoordinator: WelcomeCoordinatorEventHandler {
	func handle(_ event: WelcomeCoordinator.Event) {
		switch event {
			case .settingsTap:
				openSettings()

			case .startSetupTap:
				let vc = LoginCoordinator(eventHandler: self).makeInitial()
				navigationController?.pushViewController(vc, animated: true)
		}
	}
}

extension FirstRunCoordinator: LoginCoordinatorEventHandler {
	func handle(_ event: LoginCoordinator.Event) {
		switch event {
			case .loginTap:
				rootVC?.contentViewController = UIViewController()
				selfHandle = nil
				print("4242: loginTap")
			case .moreInfoTap:
				print("4242: moreInfoTap")
			case .settingsTap:
				openSettings()
		}
	}
}
