//
//  TrashRestoreConflictChecker.swift
//  ownCloud
//
//  Copyright © 2025 ownCloud GmbH. All rights reserved.
//

import Foundation
import ownCloudSDK
import ownCloudAppShared

enum TrashRestoreConflictChecker {
	static func checkDestinationConflict(for item: OCItem, connection: OCConnection, completion: @escaping (Error?) -> Void) {
		guard let destinationPath = item.value(forLocalAttribute: OCLocalAttribute.trashOriginalLocation) as? String,
		      !destinationPath.isEmpty else {
			completion(nil)
			return
		}

		let location = OCLocation(driveID: item.driveID, path: destinationPath)

		_ = connection.retrieveItemList(at: location, depth: 0, options: nil) { error, foundItems in
			OnMainThread {
				if error == nil, let foundItems, !foundItems.isEmpty {
					completion(TrashErrorPresentation.nameConflictNSError)
					return
				}

				completion(nil)
			}
		}
	}
}
