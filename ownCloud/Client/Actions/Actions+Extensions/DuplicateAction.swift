//
//  DuplicateAction.swift
//  ownCloud
//
//  Created by Pablo Carrascal on 15/11/2018.
//  Copyright © 2018 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2018, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import Foundation

import ownCloudSDK
import ownCloudAppShared

class DuplicateAction : Action {
	override class var identifier : OCExtensionIdentifier? { return OCExtensionIdentifier("com.owncloud.action.duplicate") }
	override class var category : ActionCategory? { return .normal }
	override class var name : String? { return OCLocalizedString("Duplicate", nil) }
	override class var locations : [OCExtensionLocationIdentifier]? { return [.moreItem, .moreDetailItem, .moreFolder, .multiSelection, .dropAction, .keyboardShortcut, .contextMenuItem, .accessibilityCustomAction] }
	override class var keyCommand : String? { return "D" }
	override class var keyModifierFlags: UIKeyModifierFlags? { return [.command] }

	// MARK: - Extension matching
	override class func applicablePosition(forContext: ActionContext) -> ActionPosition {
		if let rootItem = forContext.rootItem, !rootItem.permissions.contains(.createFile) || !rootItem.permissions.contains(.createFolder) {
			return .none
		}

		if forContext.items.filter({return $0.isRoot}).count > 0 {
			return .none
		}

		return .middle
	}

	// MARK: - Action implementation
	override func run() {
		guard context.items.count > 0 else {
			completed(with: NSError(ocError: .itemNotFound))
			return
		}

		let duplicateItems = self.context.items

		if let core = self.core {
			OnBackgroundQueue { [weak core] in
				guard let core else { return }

				for item in duplicateItems {
					self.duplicate(item, using: core)
				}
			}
		}

		self.completed()
	}

	private func duplicate(_ item: OCItem, using core: OCCore) {
		// Tag/search listings return WebDAV items without parentLocalID; prefer the cached item when available.
		let sourceItem = item.cachedEquivalent(from: core)

		guard let itemName = sourceItem.name else {
			Log.error("Error duplicating \(String(describing: sourceItem.path)) - missing name")
			return
		}

		guard let parentItem = resolveParent(for: sourceItem, using: core), let parentLocation = parentItem.location else {
			Log.error("Error duplicating \(String(describing: sourceItem.path)) - parent not found")
			return
		}

		core.suggestUnusedNameBased(on: itemName, at: parentLocation, isDirectory: sourceItem.type == .collection, using: sourceItem.type == .collection ? .numbered : .bracketed, filteredBy: nil, resultHandler: { (suggestedName, _) in
			Log.debug("Duplicating \(sourceItem.name ?? "(null)") as \(suggestedName ?? "(null)")")

			if let suggestedName, let progress = core.copy(sourceItem, to: parentItem, withName: suggestedName, options: nil, resultHandler: { (error, _, copiedItem, _) in
				if error != nil {
					Log.error("Error \(String(describing: error)) duplicating \(String(describing: copiedItem?.path ?? sourceItem.path))")
				}
			}) {
				self.publish(progress: progress)
			} else {
				Log.error("Error duplicating \(String(describing: sourceItem.path)) - no suggestedName")
			}
		})
	}

	private func resolveParent(for item: OCItem, using core: OCCore) -> OCItem? {
		if let parentItem = item.parentItem(from: core) {
			return parentItem
		}

		guard let parentLocation = item.location?.parent else {
			return nil
		}

		var fetchedParent: OCItem?
		let waitSemaphore = DispatchSemaphore(value: 0)

		_ = core.connection.retrieveItemList(at: parentLocation, depth: 0, options: nil) { error, items in
			if let error {
				Log.error("Error retrieving parent for duplicate of \(String(describing: item.path)): \(error)")
			}
			fetchedParent = items?.first
			waitSemaphore.signal()
		}

		waitSemaphore.wait()
		return fetchedParent
	}

	override class func iconForLocation(_ location: OCExtensionLocationIdentifier) -> UIImage? {
		return UIImage(named: "duplicate-file")?.withRenderingMode(.alwaysTemplate)
	}
}
