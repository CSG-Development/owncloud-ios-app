import UIKit

/// Full-screen presentation so `.custom` overlays resize with the window.
/// Without this, iPad rotation leaves the presented view (and its first responder) stale.
final class CrossDissolvePresentationController: UIPresentationController {
	override var shouldPresentInFullscreen: Bool { true }

	override var shouldRemovePresentersView: Bool { false }

	override var frameOfPresentedViewInContainerView: CGRect {
		containerView?.bounds ?? .zero
	}

	override func containerViewWillLayoutSubviews() {
		super.containerViewWillLayoutSubviews()
		presentedView?.frame = frameOfPresentedViewInContainerView
	}
}

public final class CrossDissolveTransitioningDelegate: NSObject,
	UIViewControllerTransitioningDelegate,
	UIViewControllerAnimatedTransitioning
{
	private var isDismissing = false
	private let duration: TimeInterval = 0.25

	public func presentationController(
		forPresented presented: UIViewController,
		presenting: UIViewController?,
		source: UIViewController
	) -> UIPresentationController? {
		CrossDissolvePresentationController(
			presentedViewController: presented,
			presenting: presenting
		)
	}

	public func animationController(
		forPresented presented: UIViewController,
		presenting: UIViewController,
		source: UIViewController
	) -> UIViewControllerAnimatedTransitioning? {
		isDismissing = false
		return self
	}

	public func animationController(
		forDismissed dismissed: UIViewController
	) -> UIViewControllerAnimatedTransitioning? {
		isDismissing = true
		return self
	}

	public func transitionDuration(
		using transitionContext: UIViewControllerContextTransitioning?
	) -> TimeInterval {
		return duration
	}

	public func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
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
