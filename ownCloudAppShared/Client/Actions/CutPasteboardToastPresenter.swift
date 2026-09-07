import UIKit
import ownCloudSDK

public enum CutPasteboardToastPresenter {
	private static weak var activeToast: CutPasteboardToastView?
	private static var autoDismissWorkItem: DispatchWorkItem?

	public static func show(_ message: String, on preferredAnchor: UIViewController?) {
		let toast = CutPasteboardToastView(message: message)
		toast.onDismiss = {
			dismiss(animated: true)
		}
		present(toast, preferredAnchor: preferredAnchor, autoDismissAfter: 4)
	}

	public static func dismiss(animated: Bool) {
		autoDismissWorkItem?.cancel()
		autoDismissWorkItem = nil
		guard let toast = activeToast else { return }

		let remove = {
			toast.removeFromSuperview()
			if activeToast === toast {
				activeToast = nil
			}
		}

		guard animated else {
			remove()
			return
		}

		UIView.animate(withDuration: 0.2, animations: {
			toast.alpha = 0
		}, completion: { _ in
			remove()
		})
	}

	private static func present(_ toast: CutPasteboardToastView, preferredAnchor: UIViewController?, autoDismissAfter: TimeInterval?) {
		dismiss(animated: false)

		guard let hostView = presentationHostView(preferredAnchor: preferredAnchor) else { return }

		activeToast = toast
		toast.alpha = 0
		hostView.addSubview(toast)
		hostView.bringSubviewToFront(toast)

		toast.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			toast.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor, constant: 8),
			toast.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor, constant: -8),
			toast.bottomAnchor.constraint(equalTo: hostView.bottomAnchor, constant: -8)
		])

		UIView.animate(withDuration: 0.25) {
			toast.alpha = 1
		}

		if let autoDismissAfter {
			let workItem = DispatchWorkItem {
				dismiss(animated: true)
			}
			autoDismissWorkItem = workItem
			DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter, execute: workItem)
		}
	}

	private static func presentationHostView(preferredAnchor: UIViewController?) -> UIView? {
		if let browser = resolveBrowser(from: preferredAnchor) {
			return browser.contentContainerView
		}
		if let root = UserInterfaceContext.shared.currentWindow?.rootViewController,
		   let browser = findBrowser(in: root) {
			return browser.contentContainerView
		}
		if let preferred = preferredAnchor, preferred.view.window != nil {
			return preferred.view
		}
		return UserInterfaceContext.shared.currentWindow
	}

	private static func resolveBrowser(from preferred: UIViewController?) -> BrowserNavigationViewController? {
		if let browser = preferred as? BrowserNavigationViewController {
			return browser
		}
		if let browser = preferred?.browserNavigationViewController {
			return browser
		}
		if let root = UserInterfaceContext.shared.currentWindow?.rootViewController {
			return findBrowser(in: root)
		}
		return nil
	}

	private static func findBrowser(in root: UIViewController) -> BrowserNavigationViewController? {
		if let browser = root as? BrowserNavigationViewController {
			return browser
		}
		if let browser = root.browserNavigationViewController {
			return browser
		}
		for child in root.children {
			if let browser = findBrowser(in: child) {
				return browser
			}
		}
		if let presented = root.presentedViewController {
			return findBrowser(in: presented)
		}
		return nil
	}
}
