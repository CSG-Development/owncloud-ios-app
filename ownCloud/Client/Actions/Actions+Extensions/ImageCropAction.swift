import UIKit
import QuickLook
import ObjectiveC
import ownCloudSDK
import ownCloudAppShared
import Photos
import Mantis

class ImageCropAction: Action {
    override class var identifier: OCExtensionIdentifier? { return OCExtensionIdentifier("com.owncloud.action.imagecrop") }
    override class var category: ActionCategory? { return .edit }
	override class var name: String? { return HCL10n.ImageCropAction.name }
    override class var locations: [OCExtensionLocationIdentifier]? { return [.moreItem, .moreDetailItem, .contextMenuItem, .keyboardShortcut, .accessibilityCustomAction] }
    override class var keyCommand: String? { return "K" }
    override class var keyModifierFlags: UIKeyModifierFlags? { return [.command, .shift] }

    class var supportedMimeTypes: [String] { return ["image"] }
    class var excludedMimeTypes: [String] { return ["image/gif", "image/svg", "image/x-dcraw"] }

    // MARK: - Extension matching
    override class func applicablePosition(forContext: ActionContext) -> ActionPosition {
        // only one file item that is an image
        guard forContext.items.count == 1, let item = forContext.items.first, item.type == .file, let mimeType = item.mimeType else {
            return .none
        }

        if supportedMimeTypes.contains(where: { mimeType.contains($0) }) && !excludedMimeTypes.contains(where: { mimeType.contains($0) }) {
            return .middle
        }

        return .none
    }

    override class func iconForLocation(_ location: OCExtensionLocationIdentifier) -> UIImage? {
        return UIImage(systemName: "crop")?.withRenderingMode(.alwaysTemplate)
    }

    // Swift retention instead of objc association
    private static var activeActions: [ImageCropAction] = []
    private var pendingItem: OCItem?

    private func retainSelf() {
        ImageCropAction.activeActions.append(self)
    }

    private func releaseSelf() {
        ImageCropAction.activeActions.removeAll { $0 === self }
    }

    // MARK: - Action implementation
    override func run() {
        guard context.items.count == 1, let item = context.items.first, let hostViewController = context.viewController, let core = core else {
            completed(with: NSError(ocError: .insufficientParameters))
            return
        }

        // Download the image first (HUD mirrors markup action UX)
        let hudViewController = DownloadItemsHUDViewController(core: core, downloadItems: [item]) { [weak hostViewController] error, files in

            if let error = error {
                if (error as NSError).isOCError(withCode: .cancelled) {
                    return
                }
                let appName = VendorServices.shared.appName
                let alertController = ThemedAlertController(with: OCLocalizedString("Cannot connect to ", nil) + appName, message: appName + OCLocalizedString(" couldn't download file(s)", nil), okLabel: OCLocalizedString("OK", nil), action: nil)
                hostViewController?.present(alertController, animated: true)
                return
            }

            guard let fileURL = files?.first?.url else { return }

            self.presentCropper(for: fileURL, item: item, presenter: hostViewController)
        }

        hudViewController.presentHUDOn(viewController: hostViewController)

        // Do NOT call completed() here; keep action alive until cropper finishes
    }

    private func presentCropper(for fileURL: URL, item: OCItem, presenter: UIViewController?) {
        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            return
        }

        let config = Mantis.Config()
        let cropViewController = Mantis.cropViewController(image: image, config: config)
        cropViewController.modalPresentationStyle = .fullScreen
        cropViewController.delegate = self

        self.pendingItem = item
        self.retainSelf()

        if let presenter {
            presenter.present(cropViewController, animated: true)
        } else {
            context.viewController?.present(cropViewController, animated: true)
        }
    }

    // MARK: - Save Flow
    private func requestSavingMode(for item: OCItem, completion: @escaping (QLPreviewItemEditingMode) -> Void) {
		let alertController = ThemedAlertController(title: HCL10n.ImageCropAction.SaveAlert.title, message: nil, preferredStyle: .alert)

        if item.permissions.contains(.writable) {
            alertController.addAction(UIAlertAction(title: HCL10n.ImageCropAction.SaveAlert.overwrite, style: .default, handler: { _ in
                completion(.updateContents)
            }))
        }

        if let core = core, item.parentItem(from: core)?.permissions.contains(.createFile) == true {
			alertController.addAction(UIAlertAction(title: HCL10n.ImageCropAction.SaveAlert.saveACopy, style: .default, handler: { _ in
                completion(.createCopy)
            }))
        }

		alertController.addAction(UIAlertAction(title: HCL10n.ImageCropAction.SaveAlert.discard, style: .destructive, handler: { _ in
            completion(.disabled)
        }))

        context.viewController?.present(alertController, animated: true)
    }

    private func persistCroppedImage(_ image: UIImage, for item: OCItem, savingMode: QLPreviewItemEditingMode) {
        guard let core = core else { return }

        // Determine target file name and format
        let originalName: String = item.name ?? "image.jpg"
        let targetExtension: String = ((originalName as NSString).pathExtension.isEmpty ? "jpg" : (originalName as NSString).pathExtension)
        let baseName: String = (originalName as NSString).deletingPathExtension
        let fileName: String = (baseName as NSString).appendingPathExtension(targetExtension) ?? (baseName + "." + targetExtension)

        // Encode image
        let data: Data?
        if ["jpg", "jpeg", "heic"].contains(targetExtension.lowercased()) {
            data = image.jpegData(compressionQuality: 0.9)
        } else if targetExtension.lowercased() == "png" {
            data = image.pngData()
        } else {
            data = image.jpegData(compressionQuality: 0.9)
        }
        guard let imageData = data else { return }

        // Write to temporary file
        guard
			let tmpDir = NSURL(
				fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("crop-\(UUID().uuidString)",
				isDirectory: true
			)
		else {
			return
		}

        do {
            try FileManager.default.createDirectory(
					at: tmpDir,
					withIntermediateDirectories: true,
					attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
			)
        } catch {
            return
        }

        let tmpURL = tmpDir.appendingPathComponent(fileName)
		do {
			try imageData.write(to: tmpURL, options: [.atomic])
		} catch { return }

        switch savingMode {
        case .createCopy:
            if let parentItem = item.parentItem(from: core) {
                core.importFileNamed(
					item.name,
					at: parentItem,
					from: tmpURL,
					isSecurityScoped: true,
					options: [
						.automaticConflictResolutionNameStyle: OCCoreDuplicateNameStyle.bracketed.rawValue,
						OCCoreOption.importByCopying: true
					],
					placeholderCompletionHandler: { (error, _) in
						if let error = error {
							self.present(error: error, title: OCLocalizedString("Saving edited file failed", nil))
						}
					},
					resultHandler: nil
				)
            }
        case .updateContents:
            if let parentItem = item.parentItem(from: core) {
                core.reportLocalModification(
					of: item,
					parentItem: parentItem,
					withContentsOfFileAt: tmpURL,
					isSecurityScoped: true,
					options: [ OCCoreOption.importByCopying : true ],
					placeholderCompletionHandler: { (error, _) in
						if let error = error {
							self.present(error: error, title: OCLocalizedString("Saving edited file failed", nil))
						}
					},
					resultHandler: nil
				)
            }
        default:
            break
        }
    }

    private func present(error: Error, title: String) {
        var presentationStyle: UIAlertController.Style = .actionSheet
        if UIDevice.current.isIpad { presentationStyle = .alert }
        let alertController = ThemedAlertController(
			title: title,
			message: error.localizedDescription,
			preferredStyle: presentationStyle
		)
        alertController.addAction(UIAlertAction(
			title: OCLocalizedString("OK", nil),
			style: .cancel,
			handler: nil
		))
        context.viewController?.present(alertController, animated: true)
    }
}

extension ImageCropAction: CropViewControllerDelegate {
    func cropViewControllerDidCrop(
		_ cropViewController: Mantis.CropViewController,
		cropped: UIImage,
		transformation: Mantis.Transformation,
		cropInfo: Mantis.CropInfo
	) {
        guard
			let item = self.pendingItem
		else {
            cropViewController.dismiss(animated: true) { [weak self] in
                self?.pendingItem = nil
                self?.releaseSelf()
                self?.completed()
            }
            return
        }

        cropViewController.dismiss(animated: true) { [weak self] in
            guard let self else { return }

            self.requestSavingMode(for: item) { mode in
                if mode != .disabled {
                    self.persistCroppedImage(cropped, for: item, savingMode: mode)
                }
                self.pendingItem = nil
                self.releaseSelf()
                self.completed()
            }
        }
    }

    func cropViewControllerDidFailToCrop(
		_ cropViewController: Mantis.CropViewController,
		original: UIImage
	) {
        cropViewController.dismiss(animated: true) { [weak self] in
            self?.pendingItem = nil
            self?.releaseSelf()
            self?.completed()
        }
    }

    func cropViewControllerDidCancel(
		_ cropViewController: Mantis.CropViewController,
		original: UIImage
	) {
        cropViewController.dismiss(animated: true) { [weak self] in
            self?.pendingItem = nil
            self?.releaseSelf()
            self?.completed()
        }
    }

    func cropViewControllerDidBeginResize(_ cropViewController: Mantis.CropViewController) { }

    func cropViewControllerDidEndResize(
		_ cropViewController: Mantis.CropViewController,
		original: UIImage, cropInfo: Mantis.CropInfo
	) { }
}
