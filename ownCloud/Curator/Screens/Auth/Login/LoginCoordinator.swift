import UIKit
import ownCloudAppShared

protocol LoginCoordinatorEventHandler: AnyObject {
	func handle(_ event: LoginCoordinator.Event)
}

final class LoginCoordinator {
	weak var mainVC: LoginViewController?

	private weak var eventHandler: LoginCoordinatorEventHandler?
	enum Event {
		case loginTap
		case resetPasswordTap
		case settingsTap
		case oldLoginTap
	}

	init(eventHandler: LoginCoordinatorEventHandler) {
		self.eventHandler = eventHandler
	}

	func makeInitial() -> LoginViewController {
		let vm = LoginViewModel(eventHandler: self)
		let vc = LoginViewController(viewModel: vm)
		mainVC = vc
		return vc
	}
}

extension LoginCoordinator: LoginViewModelEventHandler {
	func handle(_ event: LoginViewModel.Event) {
		switch event {
			case .loginTap:
				eventHandler?.handle(.loginTap)

			case .resetPasswordTap:
				eventHandler?.handle(.resetPasswordTap)

			case .settingsTap:
				eventHandler?.handle(.settingsTap)

			case .backToEmail:
				break

			case .unableToConnect:
				let vc = UnableToConnectViewController()
				vc.onRetry = { [weak self] in
					self?.mainVC?.viewModel.refreshDevices()
				}
				mainVC?.present(vc, animated: true)

			case .unableToDetect:
				let vc = UnableToDetectViewController()
				vc.onRetry = { [weak self] in
					self?.mainVC?.viewModel.refreshDevices()
				}
				mainVC?.present(vc, animated: true)

			case .wrongState:
				let vc = WrongStateViewController()
				vc.onRetry = { [weak self] in
					self?.mainVC?.dismiss(animated: true) {
						self?.mainVC?.viewModel.didTapLogin()
					}
				}
				mainVC?.present(vc, animated: true)

			case .setupRequired:
				let vc = SetupRequiredViewController()
				vc.onRetry = { [weak self] in
					self?.mainVC?.dismiss(animated: true) {
						self?.mainVC?.viewModel.didTapLogin()
					}
				}
				mainVC?.present(vc, animated: true)

			case .deviceStarting:
				let vc = DeviceStartingViewController()
				vc.onRetry = { [weak self] in
					self?.mainVC?.dismiss(animated: true) {
						self?.mainVC?.viewModel.didTapLogin()
					}
				}
				mainVC?.present(vc, animated: true)

			case .oldLoginTap:
				eventHandler?.handle(.oldLoginTap)

			case .developerOptionsTap:
				let viewModel = DeveloperOptionsViewModel { [weak self] in
					self?.mainVC?.viewModel.refreshDevices()
				}
				let vc = DeveloperOptionsViewController(viewModel: viewModel)
				vc.modalPresentationStyle = .overFullScreen
				vc.modalTransitionStyle = .crossDissolve
				mainVC?.present(vc, animated: true)
		}
	}
}
