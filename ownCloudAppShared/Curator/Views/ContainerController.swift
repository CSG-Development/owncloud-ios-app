import UIKit
import SnapKit

public final class ContainerController {
	public private(set) weak var currentVC: UIViewController?
    private weak var hostVC: UIViewController?
    private weak var containerView: UIView?

	public init(hostVC: UIViewController, containerView: UIView) {
        self.hostVC = hostVC
        self.containerView = containerView
    }

	public func transition(_ toVC: UIViewController, animated: Bool, animator: UIViewControllerAnimatedTransitioning? = nil, completion: (() -> Void)? = nil) {
        let _fromVC = currentVC
        guard toVC !== _fromVC else { return }

        _fromVC?.willMove(toParent: nil)
        hostVC?.addChild(toVC)

        currentVC = toVC
        toVC.view.alpha = 1

        guard let fromVC = _fromVC,
              let containerView
        else {
            containerView?.addSubview(toVC.view)
            //toVC.view.frame = containerView?.bounds ?? .zero
			toVC.view.translatesAutoresizingMaskIntoConstraints = false
			toVC.view.snp.makeConstraints { $0.edges.equalToSuperview() }
			toVC.view.setNeedsLayout()
			toVC.view.layoutIfNeeded()
            toVC.didMove(toParent: hostVC)
            completion?()
            return
        }

        let animator = animator ?? AnimatedTransition()
        toVC.view.isUserInteractionEnabled = false

        let transitionCompletion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            fromVC.view.removeFromSuperview()
            fromVC.removeFromParent()
            toVC.didMove(toParent: self.hostVC)
            toVC.view.isUserInteractionEnabled = true
            completion?()
        }

        if animated {
            let transitionContext = TransitionContext(fromVC: fromVC, toVC: toVC, container: containerView)
            transitionContext.isAnimated = animated
            transitionContext.isInteractive = false
            transitionContext.completion = transitionCompletion
            animator.animateTransition(using: transitionContext)
        } else {
            containerView.addSubview(toVC.view)
            //toVC.view.frame = containerView.bounds
            transitionCompletion(true)
			toVC.view.translatesAutoresizingMaskIntoConstraints = false
			toVC.view.snp.makeConstraints { $0.edges.equalToSuperview() }
			toVC.view.setNeedsLayout()
			toVC.view.layoutIfNeeded()
        }
    }
}

class TransitionContext: NSObject, UIViewControllerContextTransitioning {
    var containerView: UIView

    var isAnimated: Bool
    var isInteractive: Bool
    var transitionWasCancelled: Bool
    var presentationStyle: UIModalPresentationStyle
    var targetTransform: CGAffineTransform
    var completion: ((Bool) -> Void)?

    let viewControllers: NSDictionary
    let views: NSDictionary

    init(fromVC: UIViewController, toVC: UIViewController, container: UIView) {
        containerView = container
        presentationStyle = .custom
        viewControllers = [
            UITransitionContextViewControllerKey.from: fromVC,
            UITransitionContextViewControllerKey.to: toVC
        ]
        views = [
            UITransitionContextViewKey.from: fromVC.view as Any,
            UITransitionContextViewKey.to: toVC.view as Any
        ]
        isAnimated = false
        isInteractive = false
        transitionWasCancelled = false
        targetTransform = .identity
        completion = nil
    }

    func updateInteractiveTransition(_ percentComplete: CGFloat) { }
    func finishInteractiveTransition() { }
    func cancelInteractiveTransition() { }
    func pauseInteractiveTransition() { }

    func completeTransition(_ didComplete: Bool) {
        if let completion = self.completion {
            completion(didComplete)
        }
    }

    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
        // swiftlint:disable:next force_cast
        return viewControllers.value(forKey: key.rawValue) as! UIViewController?
    }

    func view(forKey key: UITransitionContextViewKey) -> UIView? {
        // swiftlint:disable:next force_cast
        return views.value(forKey: key.rawValue) as! UIView?
    }

    func initialFrame(for vc: UIViewController) -> CGRect {
        .null
    }

    func finalFrame(for vc: UIViewController) -> CGRect {
        .null
    }
}

class AnimatedTransition: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let toVC = transitionContext.viewController(forKey: .to),
            let fromVC = transitionContext.viewController(forKey: .from)
        else {
            return
        }
        transitionContext.containerView.addSubview(toVC.view)
        transitionContext.containerView.sendSubviewToBack(toVC.view)

        toVC.view.layoutIfNeeded()
        toVC.view.frame = transitionContext.containerView.bounds
        toVC.view.alpha = 1
        let animations = {
            fromVC.view.layoutIfNeeded()
            fromVC.view.alpha = 0
        }
        let completion: (Bool) -> Void = { didComplete in
            transitionContext.completeTransition(didComplete)
        }
        let duration = transitionDuration(using: transitionContext)
        UIView.animate(withDuration: duration, animations: animations, completion: completion)
    }
}
