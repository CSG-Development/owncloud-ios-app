//
//  ClearPasteboardAction.swift
//  ownCloud
//
//  Clears items previously placed on the cut pasteboard so they are no longer marked as cut.
//

import Foundation
import UIKit
import ownCloudSDK
import ownCloudAppShared

class ClearPasteboardAction : Action {
	override class var identifier : OCExtensionIdentifier? { return OCExtensionIdentifier("com.owncloud.action.clearpasteboard") }
	override class var category : ActionCategory? { return .normal }
	override class var name : String? { return HCL10n.CutPaste.ClearClipboard.name }
	override class var locations : [OCExtensionLocationIdentifier]? { return [.moreItem, .moreDetailItem, .moreFolder, .emptyFolder, .folderAction, .contextMenuItem, .accessibilityCustomAction] }

	// MARK: - Extension matching
	override class func applicablePosition(forContext: ActionContext) -> ActionPosition {
		guard !CutPasteboardState.shared.cutLocalIDs.isEmpty else {
			return .none
		}

		let location = forContext.location?.identifier

		// On item menus, only offer clear when this item is currently cut.
		if location == .moreItem || location == .moreDetailItem || location == .contextMenuItem || location == .accessibilityCustomAction {
			guard forContext.items.contains(where: { CutPasteboardState.shared.contains($0) }) else {
				return .none
			}
		}

		return .afterMiddle
	}

	// MARK: - Action implementation
	override func run() {
		UIPasteboard.general.items = []
		CutPasteboardState.shared.clear()

		OnMainThread {
			let anchor = self.context.clientContext?.presentationViewController ?? self.context.viewController
			CutPasteboardToastPresenter.show(HCL10n.CutPaste.Toast.clipboardCleared, on: anchor)
		}

		completed()
	}

	override class func iconForLocation(_ location: OCExtensionLocationIdentifier) -> UIImage? {
		return UIImage(systemName: "xmark.circle")?.withRenderingMode(.alwaysTemplate)
	}
}
