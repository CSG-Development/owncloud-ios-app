//
//  DecompressAction.swift
//  ownCloud
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

import UIKit
import ownCloudSDK
import ownCloudAppShared

class DecompressAction: Action {
	override class var identifier: OCExtensionIdentifier? { return OCExtensionIdentifier("com.owncloud.action.decompress") }
	override class var category: ActionCategory? { return .normal }
	override class var name: String? { return HCL10n.ZipAction.Decompress.name }
	override class var locations: [OCExtensionLocationIdentifier]? {
		return [.moreItem, .moreDetailItem, .contextMenuItem, .keyboardShortcut, .accessibilityCustomAction]
	}
	override class var keyCommand: String? { return "Y" }
	override class var keyModifierFlags: UIKeyModifierFlags? { return [.command, .alternate] }

	override class func applicablePosition(forContext: ActionContext) -> ActionPosition {
		guard forContext.items.count == 1, let item = forContext.items.first else {
			return .none
		}

		if item.isRoot {
			return .none
		}

		if let rootItem = forContext.rootItem, !rootItem.permissions.contains(.createFile) || !rootItem.permissions.contains(.createFolder) {
			return .none
		}

		if ZipArchiveService.isZipArchive(item) {
			return .afterMiddle
		}

		return .none
	}

	override func run() {
		guard let core = core, let hostViewController = context.viewController, context.items.count == 1, let zipItem = context.items.first else {
			ZipDebugLogging.log("DecompressAction.run: insufficient parameters")
			completed(with: NSError(ocError: .insufficientParameters))
			return
		}

		guard let parentItem = zipItem.parentItem(from: core) else {
			ZipDebugLogging.log("DecompressAction.run: parent item not found for zip")
			completed(with: NSError(ocError: .itemNotFound))
			return
		}

		ZipDebugLogging.log(item: zipItem, context: "DecompressAction.run.zipItem")
		ZipDebugLogging.log(item: parentItem, context: "DecompressAction.run.parentItem")

		ZipOperationCoordinator.shared.startDecompress(
			zipItem: zipItem,
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
