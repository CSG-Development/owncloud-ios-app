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
		case settingsTap
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

			case .developerOptionsTap:
				let viewModel = DeveloperOptionsViewModel { [weak self] in
					self?.mainVC?.viewModel.refreshDevices()
				}
				let vc = DeveloperOptionsViewController(viewModel: viewModel)
				vc.modalPresentationStyle = .overFullScreen
				vc.modalTransitionStyle = .crossDissolve
				mainVC?.present(vc, animated: true)

			case let .resetPasswordSuccess(email):
				mainVC?.showResetPasswordSuccessToast(email: email)

			case let .resetPasswordError(errorType):
				presentResetPasswordError(errorType)
		}
	}

	private func presentResetPasswordError(_ errorType: ResetPasswordErrorType) {
		switch errorType {
			case .badRequest:
				let card = CodeVerificationUnknownEmailCardViewController { [weak self] in
					self?.mainVC?.dismiss(animated: true)
				}
				presentAuthCardOverlay(card)

			case .serverError:
				let card = CodeVerification500CardViewController(
					onRetry: { [weak self] in
						self?.mainVC?.dismiss(animated: true) {
							self?.mainVC?.viewModel.didTapResetPassword()
						}
					},
					onCancel: { [weak self] in
						self?.mainVC?.dismiss(animated: true)
					}
				)
				presentAuthCardOverlay(card)

			case .generic:
				let alert = UIAlertController(
					title: HCL10n.Auth.ResetPassword.genericErrorTitle,
					message: HCL10n.Auth.ResetPassword.genericErrorMessage,
					preferredStyle: .alert
				)
				alert.addAction(UIAlertAction(title: HCL10n.Common.ok, style: .default))
				mainVC?.present(alert, animated: true)
		}
	}

	private func presentAuthCardOverlay(_ content: UIViewController) {
		let overlayVC = AuthCardOverlayViewController(content: content)
		let animator = CrossDissolveTransitioningDelegate()
		overlayVC.transitioningDelegate = animator
		overlayVC.modalPresentationStyle = .custom
		mainVC?.present(overlayVC, animated: true)
	}
}
