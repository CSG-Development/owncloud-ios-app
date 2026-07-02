//
//  TrashDebugLogging.swift
//  ownCloudAppShared
//
//  Copyright © 2025 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2025, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import Foundation
import ownCloudSDK

public enum TrashDebugLogging {
	public static let tag = ["Trash"]

	private static var sdkObserverRegistered = false

	public static func registerSDKLogObserverIfNeeded() {
		guard !sdkObserverRegistered else { return }
		sdkObserverRegistered = true

		NotificationCenter.default.addObserver(
			forName: NSNotification.Name("OCTrashDebugLogNotification"),
			object: nil,
			queue: nil
		) { notification in
			if let message = notification.userInfo?["message"] as? String {
				log("SDK: \(message)")
			}
		}
	}

	public static func log(_ message: String) {
		Log.debug(tagged: tag, "%@", message)
	}

	public static func log(item: OCItem, context: String) {
		let originalFilename = item.value(forLocalAttribute: OCLocalAttribute.trashOriginalFilename) as? String
		let originalLocation = item.value(forLocalAttribute: OCLocalAttribute.trashOriginalLocation) as? String
		let deletionTimestamp = item.value(forLocalAttribute: OCLocalAttribute.trashDeletionTimestamp)
		let isTrashItem = item.value(forLocalAttribute: OCLocalAttribute.trashItem) != nil

		log("""
		\(context): \
		name=\(Log.mask(item.name ?? "nil")) \
		path=\(Log.mask(item.path ?? "nil")) \
		type=\(item.type.rawValue) \
		mimeType=\(item.mimeType ?? "nil") \
		fileID=\(item.fileID ?? "nil") \
		driveID=\(item.driveID ?? "nil") \
		eTag=\(item.eTag ?? "nil") \
		deletionTimestamp=\(String(describing: deletionTimestamp)) \
		thumbnailAvailability=\(item.thumbnailAvailability.rawValue) \
		trashItem=\(isTrashItem) \
		originalFilename=\(Log.mask(originalFilename ?? "nil")) \
		originalLocation=\(Log.mask(originalLocation ?? "nil"))
		""")
	}
}
