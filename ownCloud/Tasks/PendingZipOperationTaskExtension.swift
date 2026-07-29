import Foundation
import ownCloudSDK
import ownCloudAppShared

class PendingZipOperationTaskExtension: ScheduledTaskAction {
	override class var identifier: OCExtensionIdentifier? { return OCExtensionIdentifier("com.owncloud.action.pending_zip_operation") }
	override class var locations: [OCExtensionLocationIdentifier]? {
		return [.appDidComeToForeground, .appLaunch, .appBackgroundFetch]
	}

	override func run(background: Bool) {
		ZipDebugLogging.log("PendingZipOperationTaskExtension: resuming pending zip jobs background=\(background)")
		ZipOperationCoordinator.shared.resumePendingJobs()
		completed()
	}
}
