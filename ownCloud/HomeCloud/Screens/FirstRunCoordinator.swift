import ownCloudAppShared
import ownCloudApp

final class FirstRunCoordinator {
	private weak var navigationController: UINavigationController?

	func makeInitial() -> ThemeNavigationController {
		let vc = makeWelcomeVC()
		let nc = ThemeNavigationController(rootViewController: vc)
		nc.setNavigationBarHidden(true, animated: false)
		self.navigationController = nc
		return nc
	}

	private func makeWelcomeVC() -> WelcomeViewController {
		let vc = WelcomeViewController()
		vc.backgroundImage =
			Branding.shared.brandedImageNamed(.brandBackground)

		vc.onStartSetupTap = { [weak self] in
			let vc = LoginViewController()//ServerAddressViewController()
			self?.navigationController?.pushViewController(vc, animated: true)
		}

		vc.onSettingsTap = { [weak self] in
			let nc = ThemeNavigationController(rootViewController: SettingsViewController())
			nc.modalPresentationStyle = .fullScreen
			self?.navigationController?.present(nc, animated: true)
		}
		return vc
	}
}
