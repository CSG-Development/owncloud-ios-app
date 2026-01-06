import Foundation

@objcMembers
public final class AppExtensionBootstrap: NSObject {
	private static let lock = NSLock()
	private static var didSetup = false

	/// Ensure dynamic URL switching (HCContext + reachability) is configured for extension processes.
	public static func setupDynamicURLSwitching() {
		lock.lock()
		defer { lock.unlock() }

		guard didSetup == false else { return }
		didSetup = true

		HCContext.shared.setup()
	}
}

