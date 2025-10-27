import ownCloudAppShared
import ownCloudApp

final class OldFirstRunCoordinator {
	private weak var navigationController: UINavigationController?
	private weak var rootVC: AppRootViewController?
	private var selfHandle: AnyObject?

	init(rootVC: AppRootViewController?) {
		self.rootVC = rootVC
	}

	func makeInitial() -> ThemeNavigationController {
		let vc = OldLoginCoordinator(eventHandler: self).makeInitial()
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

extension OldFirstRunCoordinator: OldLoginCoordinatorEventHandler {
	func handle(_ event: OldLoginCoordinator.Event) {
		switch event {
			case .loginTap:
				rootVC?.contentViewController = UIViewController()
				selfHandle = nil

			case .resetPasswordTap:
				UIApplication.shared.open(HCConfig.resetPasswordLink)

			case .settingsTap:
				openSettings()
		}
	}
}
