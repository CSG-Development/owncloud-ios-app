//
//  TagSearchSyncTaskAction.swift
//  ownCloud
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

import Foundation
import ownCloudSDK
import ownCloudAppShared

/// Periodically refreshes tag↔file associations for local tag search (Android WorkManager parity).
class TagSearchSyncTaskAction: ScheduledTaskAction {

	override class var identifier: OCExtensionIdentifier? {
		OCExtensionIdentifier("com.owncloud.action.tag_search_sync")
	}

	override class var locations: [OCExtensionLocationIdentifier]? {
		[.appDidBecomeBackgrounded, .appBackgroundFetch, .appLaunch]
	}

	override class var features: [String: Any]? {
		[FeatureKeys.runOnWifi: true]
	}

	override func run(background: Bool) {
		self.completion = { task in
			Log.log("Scheduled tag sync finished: \(String(describing: task.result))")
		}

		super.run(background: background)

		let syncGroup = DispatchGroup()

		for bookmark in OCBookmarkManager.shared.bookmarks {
			syncGroup.enter()
			AccountTagSyncService.shared.syncIfNeeded(for: bookmark, force: false) {
				syncGroup.leave()
			}
		}

		syncGroup.wait()
		self.result = .success(nil)
		self.completed()
	}
}
