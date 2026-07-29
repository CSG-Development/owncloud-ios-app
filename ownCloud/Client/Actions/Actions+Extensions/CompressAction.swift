//
//  CompressAction.swift
//  ownCloud
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

import UIKit
import ownCloudSDK
import ownCloudAppShared

class CompressAction: Action {
	override class var identifier: OCExtensionIdentifier? { return OCExtensionIdentifier("com.owncloud.action.compress") }
	override class var category: ActionCategory? { return .normal }
	override class var name: String? { return HCL10n.ZipAction.Compress.name }
	override class var locations: [OCExtensionLocationIdentifier]? {
		return [.moreItem, .moreDetailItem, .moreFolder, .multiSelection, .contextMenuItem, .keyboardShortcut, .accessibilityCustomAction]
	}
	override class var keyCommand: String? { return "Y" }
	override class var keyModifierFlags: UIKeyModifierFlags? { return [.command, .shift] }

	override class func applicablePosition(forContext: ActionContext) -> ActionPosition {
		if forContext.items.filter({ $0.isRoot }).count > 0 {
			return .none
		}

		if let rootItem = forContext.rootItem, !rootItem.permissions.contains(.createFile) {
			return .none
		}

		return .afterMiddle
	}

	override func run() {
		guard let core = core, let hostViewController = context.viewController, context.items.count > 0 else {
			ZipDebugLogging.log("CompressAction.run: insufficient parameters")
			completed(with: NSError(ocError: .insufficientParameters))
			return
		}

		guard let firstItem = context.items.first, let parentItem = firstItem.parentItem(from: core) else {
			ZipDebugLogging.log("CompressAction.run: parent item not found")
			completed(with: NSError(ocError: .itemNotFound))
			return
		}

		ZipDebugLogging.log(items: context.items, context: "CompressAction.run.items")
		ZipDebugLogging.log(item: parentItem, context: "CompressAction.run.parentItem")

		ZipOperationCoordinator.shared.startCompress(
			items: context.items,
			parentItem: parentItem,
			core: core,
			hostViewController: hostViewController
		)
		completed()
	}

	override class func iconForLocation(_ location: OCExtensionLocationIdentifier) -> UIImage? {
		return UIImage(systemName: "doc.zipper")?.withRenderingMode(.alwaysTemplate)
	}
}
