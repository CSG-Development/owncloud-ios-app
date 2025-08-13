import ownCloudAppShared
import ownCloudApp

final class FirstRunCoordinator {
	private weak var navigationController: UINavigationController?
	private weak var rootVC: AppRootViewController?
	private var selfHandle: AnyObject?

	init(rootVC: AppRootViewController?) {
		self.rootVC = rootVC
	}

	func makeInitial() -> ThemeNavigationController {
		let vc = LoginCoordinator(eventHandler: self).makeInitial()
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

extension FirstRunCoordinator: LoginCoordinatorEventHandler {
	func handle(_ event: LoginCoordinator.Event) {
		switch event {
			case .loginTap:
				rootVC?.contentViewController = UIViewController()
				selfHandle = nil
			case .resetPasswordTap:
				if let url = URL(string: "https://seagate.com/") {
					UIApplication.shared.open(url)
				}
			case .settingsTap:
				openSettings()
		}
	}
}
