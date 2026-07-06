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

	private static var activeActions: [CompressAction] = []

	private func retainSelf() {
		CompressAction.activeActions.append(self)
	}

	private func releaseSelf() {
		CompressAction.activeActions.removeAll { $0 === self }
	}

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
		retainSelf()

		let hudViewController = ZipOperationHUDViewController(core: core, operation: .compress(items: context.items, parentItem: parentItem)) { [weak self, weak hostViewController] error, result in
			guard let self = self else { return }

			if let error = error {
				if (error as NSError).isOCError(withCode: .cancelled) {
					ZipDebugLogging.log("CompressAction: cancelled by user")
					self.releaseSelf()
					return
				}

				ZipDebugLogging.log(error: error, context: "CompressAction.HUD")
				OnMainThread {
					let appName = VendorServices.shared.appName
					let alertController = ThemedAlertController(with: OCLocalizedString("Cannot connect to ", nil) + appName, message: error.localizedDescription, okLabel: HCL10n.Common.ok, action: nil)
					hostViewController?.present(alertController, animated: true)
					self.completed(with: error)
					self.releaseSelf()
				}
				return
			}

			guard case .compress(let archiveURL, let fileName, let parentItem) = result?.kind else {
				ZipDebugLogging.log("CompressAction: HUD finished without compress result")
				OnMainThread {
					self.completed(with: NSError(ocError: .internal))
					self.releaseSelf()
				}
				return
			}

			ZipDebugLogging.log(url: archiveURL, context: "CompressAction.beginUpload")
			ZipDebugLogging.log(item: parentItem, context: "CompressAction.uploadParentItem")
			ZipDebugLogging.log("CompressAction.beginUpload: fileName=\(Log.mask(fileName))")

			OnMainThread {
				if let uploadProgress = archiveURL.upload(with: core, at: parentItem, alternativeName: fileName, completionHandler: { item, error in
					try? FileManager.default.removeItem(at: archiveURL)
					ZipDebugLogging.log(url: archiveURL, context: "CompressAction.archiveURL(afterUploadCleanup)")

					if let error = error {
						ZipDebugLogging.log(error: error, context: "CompressAction.upload")
						OnMainThread {
							let appName = VendorServices.shared.appName
							let alertController = ThemedAlertController(with: OCLocalizedString("Cannot connect to ", nil) + appName, message: error.localizedDescription, okLabel: HCL10n.Common.ok, action: nil)
							hostViewController?.present(alertController, animated: true)
							self.completed(with: error)
							self.releaseSelf()
						}
						return
					}

					if let item = item {
						ZipDebugLogging.log(item: item, context: "CompressAction.uploadedItem")
					}
					ZipDebugLogging.log("CompressAction: upload completed successfully")
					self.completed()
					self.releaseSelf()
				}) {
					ZipDebugLogging.log("CompressAction: upload progress started")
					self.publish(progress: uploadProgress)
				} else {
					ZipDebugLogging.log("CompressAction: upload returned nil progress")
					try? FileManager.default.removeItem(at: archiveURL)
					OnMainThread {
						self.completed(with: NSError(ocError: .internal))
						self.releaseSelf()
					}
				}
			}
		}

		hudViewController.presentHUDOn(viewController: hostViewController)
		ZipDebugLogging.log("CompressAction: HUD presented")
	}

	override class func iconForLocation(_ location: OCExtensionLocationIdentifier) -> UIImage? {
		return UIImage(systemName: "doc.zipper")?.withRenderingMode(.alwaysTemplate)
	}
}
