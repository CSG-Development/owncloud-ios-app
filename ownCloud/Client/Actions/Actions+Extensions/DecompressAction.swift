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

	private static var activeActions: [DecompressAction] = []

	private func retainSelf() {
		DecompressAction.activeActions.append(self)
	}

	private func releaseSelf() {
		DecompressAction.activeActions.removeAll { $0 === self }
	}

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
		retainSelf()

		let hudViewController = ZipOperationHUDViewController(core: core, operation: .decompress(zipItem: zipItem, parentItem: parentItem)) { [weak self, weak hostViewController] error, result in
			guard let self = self else { return }

			if let error = error {
				if (error as NSError).isOCError(withCode: .cancelled) {
					ZipDebugLogging.log("DecompressAction: cancelled by user")
					self.releaseSelf()
					return
				}

				ZipDebugLogging.log(error: error, context: "DecompressAction.HUD")
				OnMainThread {
					let appName = VendorServices.shared.appName
					let alertController = ThemedAlertController(with: OCLocalizedString("Cannot connect to ", nil) + appName, message: error.localizedDescription, okLabel: HCL10n.Common.ok, action: nil)
					hostViewController?.present(alertController, animated: true)
					self.completed(with: error)
					self.releaseSelf()
				}
				return
			}

			guard case .decompress(let extractURL, let parentItem) = result?.kind else {
				ZipDebugLogging.log("DecompressAction: HUD finished without decompress result")
				OnMainThread {
					self.completed(with: NSError(ocError: .internal))
					self.releaseSelf()
				}
				return
			}

			ZipDebugLogging.log(url: extractURL, context: "DecompressAction.beginUpload")
			OnMainThread {
				ZipArchiveService.uploadExtractedContents(at: extractURL, to: parentItem, core: core, publishProgress: { uploadProgress in
					self.publish(progress: uploadProgress)
				}, completion: { error in
					try? FileManager.default.removeItem(at: extractURL)
					ZipDebugLogging.log(url: extractURL, context: "DecompressAction.extractURL(afterUploadCleanup)")

					if let error = error {
						ZipDebugLogging.log(error: error, context: "DecompressAction.uploadExtractedContents")
						OnMainThread {
							let appName = VendorServices.shared.appName
							let alertController = ThemedAlertController(with: OCLocalizedString("Cannot connect to ", nil) + appName, message: error.localizedDescription, okLabel: HCL10n.Common.ok, action: nil)
							hostViewController?.present(alertController, animated: true)
							self.completed(with: error)
							self.releaseSelf()
						}
						return
					}

					ZipDebugLogging.log("DecompressAction: upload completed successfully")
					self.completed()
					self.releaseSelf()
				})
			}
		}

		hudViewController.presentHUDOn(viewController: hostViewController)
		ZipDebugLogging.log("DecompressAction: HUD presented")
	}

	override class func iconForLocation(_ location: OCExtensionLocationIdentifier) -> UIImage? {
		return UIImage(systemName: "doc.zipper")?.withRenderingMode(.alwaysTemplate)
	}
}
