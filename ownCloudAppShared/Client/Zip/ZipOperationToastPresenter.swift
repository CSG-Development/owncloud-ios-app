import UIKit
import ownCloudSDK

public enum ZipOperationToastPresenter {
	private static weak var activeToast: ZipOperationToastView?
	private static var autoDismissWorkItem: DispatchWorkItem?

	public static func showSuccess(
		kind: ZipOperationRecord.Kind,
		itemCount: Int = 0,
		on preferredAnchor: UIViewController?,
		onView: @escaping () -> Void
	) {
		let message: String
		switch kind {
		case .compress:
			message = HCL10n.ZipAction.Success.itemsCompressed(max(itemCount, 1))
		case .decompress:
			message = HCL10n.ZipAction.Success.archiveExtracted
		}

		let toast = ZipOperationToastView(message: message, style: .success)
		toast.onView = {
			dismiss(animated: true)
			onView()
		}
		present(toast, preferredAnchor: preferredAnchor, autoDismissAfter: 4)
	}

	public static func showError(
		_ error: ZipArchiveError,
		kind: ZipOperationRecord.Kind,
		on preferredAnchor: UIViewController?,
		onRetry: (() -> Void)? = nil,
		onDismissWithoutRetry: (() -> Void)? = nil
	) {
		let toast = ZipOperationToastView(message: error.localizedMessage(for: kind), style: .error)
		toast.configureErrorActions(showsRetry: error.showsRetry)
		toast.onDismiss = {
			dismiss(animated: true)
			onDismissWithoutRetry?()
		}
		if error.showsRetry, let onRetry {
			toast.onRetry = {
				dismiss(animated: true)
				onRetry()
			}
		}
		present(toast, preferredAnchor: preferredAnchor, autoDismissAfter: 4)
	}

	public static func revealItem(
		_ item: OCItem,
		parentLocationKey: String,
		from preferredAnchor: UIViewController?,
		clientContext: ClientContext?,
		core: OCCore? = nil
	) {
		let browser = resolveBrowser(from: preferredAnchor)
			?? resolveBrowser(from: resolvePresentationAnchor(preferred: preferredAnchor))
		// Only the browser's current content counts as visible — a stale FileList behind a
		// preview must not swallow the tap with an off-screen highlight.
		let visibleFileList = browser?.contentViewController as? FileListViewController
		let context = resolveClientContext(
			preferred: clientContext,
			anchor: visibleFileList ?? preferredAnchor,
			browser: browser,
			core: core ?? clientContext?.core
		)
		guard let context else { return }

		if context.browserController == nil {
			context.browserController = browser
		}

		if let fileList = visibleFileList,
		   let currentLocationKey = ZipOperationRecord.locationKey(for: fileList.location),
		   ZipOperationRecord.locationKeysLooselyMatch(currentLocationKey, parentLocationKey) {
			fileList.highlightItem(withReference: item.dataItemReference)
			return
		}

		_ = item.revealItem(
			from: visibleFileList ?? preferredAnchor,
			with: context,
			animated: true,
			pushViewController: true,
			completion: nil
		)
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

	private static func present(_ toast: ZipOperationToastView, preferredAnchor: UIViewController?, autoDismissAfter: TimeInterval?) {
		dismiss(animated: false)

		guard let hostView = presentationHostView(preferredAnchor: preferredAnchor) else { return }

		activeToast = toast
		toast.alpha = 0
		hostView.addSubview(toast)
		hostView.bringSubviewToFront(toast)

		toast.translatesAutoresizingMaskIntoConstraints = false
		// Sit just above the tab bar (content container ends there) with 8pt inset on all three sides.
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
				if let toast = activeToast, let onDismiss = toast.onDismiss {
					onDismiss()
				} else {
					dismiss(animated: true)
				}
			}
			autoDismissWorkItem = workItem
			DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter, execute: workItem)
		}
	}

	private static func presentationHostView(preferredAnchor: UIViewController?) -> UIView? {
		// Prefer the browser content area so the toast sits above the custom tab bar.
		if let browser = resolveBrowser(from: preferredAnchor) {
			return browser.contentContainerView
		}
		if let root = UserInterfaceContext.shared.currentWindow?.rootViewController,
		   let browser = findBrowser(in: root) {
			return browser.contentContainerView
		}
		if let anchor = resolvePresentationAnchor(preferred: preferredAnchor),
		   anchor.view.window != nil {
			return anchor.view
		}
		return UserInterfaceContext.shared.currentWindow
	}

	public static func resolvePresentationAnchor(preferred: UIViewController?) -> UIViewController? {
		if let preferred, preferred.view.window != nil {
			return preferred
		}
		if let browser = resolveBrowser(from: preferred) {
			return browser.contentViewController ?? browser
		}
		if let root = UserInterfaceContext.shared.currentWindow?.rootViewController {
			if let browser = findBrowser(in: root) {
				return browser.contentViewController ?? browser
			}
			return root.topMostViewController
		}
		return preferred
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

	private static func resolveClientContext(
		preferred: ClientContext?,
		anchor: UIViewController?,
		browser: BrowserNavigationViewController?,
		core: OCCore?
	) -> ClientContext? {
		if let preferred {
			return preferred
		}
		if let context = (anchor as? FileBrowserContent)?.clientContext {
			return context
		}
		if let context = (browser?.contentViewController as? FileBrowserContent)?.clientContext {
			return context
		}
		if let context = browser?.clientContextProvider?() {
			return context
		}
		guard let core else { return nil }
		return ClientContext(core: core, modifier: { context in
			context.browserController = browser
			context.originatingViewController = anchor
		})
	}
}
