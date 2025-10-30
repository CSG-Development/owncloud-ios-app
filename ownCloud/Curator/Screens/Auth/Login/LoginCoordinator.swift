import UIKit

protocol LoginCoordinatorEventHandler: AnyObject {
	func handle(_ event: LoginCoordinator.Event)
}

final class LoginCoordinator {
	weak var mainVC: LoginViewController?
    private var codeVerificationAnimator: CrossDissolveTransitioningDelegate?

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

            case let .emailVerification(email):
                let vm = CodeVerificationViewModel(eventHandler: self, email: email)
                let vc = CodeVerificationViewController(viewModel: vm)
					let animator = CrossDissolveTransitioningDelegate()
					vc.transitioningDelegate = animator
					vc.modalPresentationStyle = .custom
					codeVerificationAnimator = animator
                mainVC?.present(vc, animated: true)

			case .oldLoginTap:
				eventHandler?.handle(.oldLoginTap)
		}
	}
}

extension LoginCoordinator: CodeVerificationViewModelEventHandler {
	func handle(_ event: CodeVerificationViewModel.Event) {
        switch event {
            case .verifyTap:
				mainVC?.dismiss(animated: true, completion: { [weak self] in
					self?.mainVC?.viewModel.advanceToDeviceSelection()
				})

            case .resetPasswordTap:
                break

            case .settingsTap:
                break
        }
    }
}

// MARK: - Cross-dissolve transition animator
private final class CrossDissolveTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning {
	private var isDismissing = false
	private let duration: TimeInterval = 0.25

	func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		isDismissing = false
		return self
	}

	func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
		isDismissing = true
		return self
	}

	func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
		return duration
	}

	func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
		let containerView = transitionContext.containerView

		if isDismissing {
			guard let fromView = transitionContext.view(forKey: .from) else {
				transitionContext.completeTransition(false)
				return
			}
			containerView.addSubview(fromView)
			UIView.animate(withDuration: duration, animations: {
				fromView.alpha = 0
			}, completion: { _ in
				transitionContext.completeTransition(true)
			})
		} else {
			guard let toView = transitionContext.view(forKey: .to),
					let toVC = transitionContext.viewController(forKey: .to) else {
				transitionContext.completeTransition(false)
				return
			}
			toView.frame = transitionContext.finalFrame(for: toVC)
			toView.alpha = 0
			containerView.addSubview(toView)
			UIView.animate(withDuration: duration, animations: {
				toView.alpha = 1
			}, completion: { _ in
				transitionContext.completeTransition(true)
			})
		}
	}
}
