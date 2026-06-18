import Foundation
import UIKit

/// Installs UIApplication foreground notifications and forwards changes to the coordinator actor.
final class ConnectivityLifecycleObserver {
	private var tokens: [NSObjectProtocol] = []
	private(set) var isInstalled = false

	func installIfNeeded(onForegroundChange: @escaping @Sendable (Bool) -> Void) {
		guard !isInstalled else { return }
		isInstalled = true
		guard !Bundle.main.bundlePath.hasSuffix(".appex") else { return }

		let becameActive = NotificationCenter.default.addObserver(
			forName: UIApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { _ in onForegroundChange(true) }

		let resignedActive = NotificationCenter.default.addObserver(
			forName: UIApplication.willResignActiveNotification,
			object: nil,
			queue: .main
		) { _ in onForegroundChange(false) }

		tokens = [becameActive, resignedActive]
		// APPLICATION_EXTENSION_API_ONLY — cannot read UIApplication.shared here.
		// setup() runs during launch; didBecomeActive will correct state if needed.
		onForegroundChange(true)
	}

	func remove() {
		for token in tokens {
			NotificationCenter.default.removeObserver(token)
		}
		tokens = []
		isInstalled = false
	}
}
