//
//  ZipOperationHUDViewController.swift
//  ownCloud
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

import UIKit
import ownCloudSDK
import ownCloudAppShared

struct ZipOperationResult {
	enum Kind {
		case compress(archiveURL: URL, fileName: String, parentItem: OCItem)
		case decompress(extractURL: URL, parentItem: OCItem)
	}

	let kind: Kind
}

typealias ZipOperationHUDCompletionHandler = (Error?, ZipOperationResult?) -> Void

class ZipOperationHUDViewController: CardViewController {
	enum Operation {
		case compress(items: [OCItem], parentItem: OCItem)
		case decompress(zipItem: OCItem, parentItem: OCItem)
	}

	private enum PhaseWeight {
		static let download: Int64 = 550
		static let archive: Int64 = 450
		static let total: Int64 = download + archive
	}

	private let operation: Operation
	private weak var core: OCCore?
	private var completion: ZipOperationHUDCompletionHandler?

	private let messageLabel = UILabel()
	private let progressView = ThemeCSSProgressView(progressViewStyle: .bar)
	private let cancelButton = ThemeRoundedButton(withSelectors: [.primary, .filled])
	private let progressSummarizer = ProgressSummarizer()

	private let overallProgress = Progress(totalUnitCount: PhaseWeight.total)
	private lazy var downloadPhase = Progress(totalUnitCount: PhaseWeight.download, parent: overallProgress, pendingUnitCount: PhaseWeight.download)
	private lazy var archivePhase = Progress(totalUnitCount: PhaseWeight.archive, parent: overallProgress, pendingUnitCount: PhaseWeight.archive)

	private var progressObservations: [NSKeyValueObservation] = []
	private var activeProgresses: [Progress] = []
	private var cancelled = false
	private var downloadError: Error?
	private var archivePlan: ZipArchivePlan?

	init(core: OCCore, operation: Operation, completion: @escaping ZipOperationHUDCompletionHandler) {
		self.core = core
		self.operation = operation
		self.completion = completion

		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		progressSummarizer.removeObserver(self)
		progressObservations.removeAll()
	}

	override func loadView() {
		let containerInsets = UIEdgeInsets(top: 20, left: 30, bottom: 20, right: 30)
		let messageProgressSpacing: CGFloat = 15
		let progressCancelSpacing: CGFloat = 25
		let containerView = UIView()

		super.loadView()

		cancelButton.setTitle(HCL10n.Common.cancel, for: .normal)
		cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

		messageLabel.text = HCL10n.ZipAction.Progress.preparing
		messageLabel.sizeToFit()
		messageLabel.setContentHuggingPriority(.required, for: .vertical)
		progressView.setContentHuggingPriority(.required, for: .vertical)
		cancelButton.setContentHuggingPriority(.required, for: .vertical)

		messageLabel.translatesAutoresizingMaskIntoConstraints = false
		progressView.translatesAutoresizingMaskIntoConstraints = false
		cancelButton.translatesAutoresizingMaskIntoConstraints = false
		containerView.translatesAutoresizingMaskIntoConstraints = false

		containerView.addSubview(messageLabel)
		containerView.addSubview(progressView)
		containerView.addSubview(cancelButton)
		view.addSubview(containerView)

		NSLayoutConstraint.activate([
			messageLabel.leftAnchor.constraint(equalTo: containerView.leftAnchor),
			messageLabel.rightAnchor.constraint(equalTo: containerView.rightAnchor),
			progressView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
			progressView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
			cancelButton.leftAnchor.constraint(equalTo: containerView.leftAnchor),
			cancelButton.rightAnchor.constraint(equalTo: containerView.rightAnchor),
			messageLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
			progressView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: messageProgressSpacing),
			cancelButton.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: progressCancelSpacing),
			cancelButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
			containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: containerInsets.top),
			containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -containerInsets.bottom),
			containerView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: containerInsets.left),
			containerView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -containerInsets.right)
		])
	}

	private func onMain(_ block: @escaping () -> Void) {
		if Thread.isMainThread {
			block()
		} else {
			OnMainThread(block)
		}
	}

	private func dismissWithFinish(error: Error?, result: ZipOperationResult? = nil) {
		onMain {
			self.dismiss(animated: true) {
				self.finish(error: error, result: result)
			}
		}
	}

	func presentHUDOn(viewController: UIViewController) {
		switch operation {
		case .compress(let items, let parentItem):
			ZipDebugLogging.log("ZipOperationHUD.presentHUD: compress")
			ZipDebugLogging.log(items: items, context: "ZipOperationHUD.presentHUD.items")
			ZipDebugLogging.log(item: parentItem, context: "ZipOperationHUD.presentHUD.parent")
		case .decompress(let zipItem, let parentItem):
			ZipDebugLogging.log("ZipOperationHUD.presentHUD: decompress")
			ZipDebugLogging.log(item: zipItem, context: "ZipOperationHUD.presentHUD.zipItem")
			ZipDebugLogging.log(item: parentItem, context: "ZipOperationHUD.presentHUD.parent")
		}

		overallProgress.localizedDescription = HCL10n.ZipAction.Progress.preparing

		progressSummarizer.addObserver(self, notificationBlock: { [weak self] _, summary in
			OnMainThread {
				guard let self = self else { return }
				self.messageLabel.text = summary.message ?? self.overallProgress.localizedDescription
				summary.update(progressView: self.progressView)
			}
		})

		progressSummarizer.startTracking(progress: overallProgress)
		progressSummarizer.update()

		viewController.present(asCard: self, animated: true, withHandle: false, dismissable: false) { [weak self] in
			self?.beginDownload()
		}
	}

	@objc private func cancel() {
		ZipDebugLogging.log("ZipOperationHUD.cancel: user cancelled operation")
		cancelled = true
		for progress in activeProgresses {
			progress.cancel()
		}
		overallProgress.cancel()

		dismissWithFinish(error: NSError(ocError: .cancelled))
	}

	private func beginDownload() {
		guard let core = core, !cancelled else {
			ZipDebugLogging.log("ZipOperationHUD.beginDownload: aborted — core missing or cancelled")
			dismissWithFinish(error: NSError(ocError: .internal))
			return
		}

		switch operation {
		case .compress(let selectedItems, _):
			ZipDebugLogging.log("ZipOperationHUD.beginDownload: compress \(selectedItems.count) item(s)")
			ZipArchiveService.collectArchivePlan(for: selectedItems, core: core) { [weak self] result in
				OnMainThread {
					guard let self = self, !self.cancelled else { return }

					switch result {
					case .failure(let error):
						ZipDebugLogging.log(error: error, context: "ZipOperationHUD.collectArchivePlan")
						self.dismissWithFinish(error: error)
					case .success(let plan):
						ZipDebugLogging.log(plan: plan, context: "ZipOperationHUD.collectArchivePlan")
						self.archivePlan = plan
						self.downloadArchivePlan(plan)
					}
				}
			}

		case .decompress(let zipItem, let parentItem):
			ZipDebugLogging.log(item: zipItem, context: "ZipOperationHUD.beginDownload.decompress")
			ZipDebugLogging.log(item: parentItem, context: "ZipOperationHUD.beginDownload.parent")
			downloadZipItem(zipItem, parentItem: parentItem)
		}
	}

	private func downloadZipItem(_ zipItem: OCItem, parentItem: OCItem) {
		guard let core = core, !cancelled else {
			ZipDebugLogging.log("ZipOperationHUD.downloadZipItem: aborted — core missing or cancelled")
			dismissWithFinish(error: NSError(ocError: .internal))
			return
		}

		if core.localCopy(of: zipItem) != nil, let file = zipItem.file(with: core), let archiveURL = file.url {
			ZipDebugLogging.log("ZipOperationHUD.downloadZipItem: using existing local copy")
			ZipDebugLogging.log(url: archiveURL, context: "ZipOperationHUD.downloadZipItem.archiveURL")
			core.registerUsage(of: zipItem, completionHandler: nil)
			downloadPhase.completedUnitCount = PhaseWeight.download
			progressSummarizer.update()
			performDecompress(archiveURL: archiveURL, parentItem: parentItem)
			return
		}

		ZipDebugLogging.log("ZipOperationHUD.downloadZipItem: downloading zip from server")
		updatePhaseMessage(HCL10n.ZipAction.Progress.downloading)

		let itemSlice = Progress(totalUnitCount: PhaseWeight.download, parent: downloadPhase, pendingUnitCount: PhaseWeight.download)

		if let progress = core.downloadItem(zipItem, options: [
			.returnImmediatelyIfOfflineOrUnavailable: true,
			.addTemporaryClaimForPurpose: OCCoreClaimPurpose.view.rawValue
		], resultHandler: { [weak self] error, _, _, file in
			guard let self = self else { return }

			if let error = error {
				ZipDebugLogging.log(error: error, context: "ZipOperationHUD.downloadZipItem")
				Log.error("ZipOperationHUDViewController: error \(String(describing: error)) downloading \(String(describing: zipItem.path))")
				self.dismissWithFinish(error: error)
				return
			}

			guard let archiveURL = file?.url else {
				ZipDebugLogging.log("ZipOperationHUD.downloadZipItem: download succeeded but file URL is nil")
				self.dismissWithFinish(error: NSError(ocError: .internal))
				return
			}

			ZipDebugLogging.log(url: archiveURL, context: "ZipOperationHUD.downloadZipItem.downloadedArchiveURL")

			if let claim = file?.claim {
				self.core?.remove(claim, on: zipItem, afterDeallocationOf: [self])
			}

			itemSlice.completedUnitCount = PhaseWeight.download
			self.progressSummarizer.update()
			self.performDecompress(archiveURL: archiveURL, parentItem: parentItem)
		}) {
			bridge(progress, into: itemSlice)
		} else {
			ZipDebugLogging.log("ZipOperationHUD.downloadZipItem: core.downloadItem returned nil")
			dismissWithFinish(error: NSError(ocError: .internal))
		}
	}

	private func downloadArchivePlan(_ plan: ZipArchivePlan) {
		guard core != nil, !cancelled else {
			ZipDebugLogging.log("ZipOperationHUD.downloadArchivePlan: aborted — core missing or cancelled")
			dismissWithFinish(error: NSError(ocError: .internal))
			return
		}

		ZipDebugLogging.log(plan: plan, context: "ZipOperationHUD.downloadArchivePlan")

		if plan.fileEntries.isEmpty {
			ZipDebugLogging.log("ZipOperationHUD.downloadArchivePlan: no files to download — proceeding to compress empty folders only")
			downloadPhase.completedUnitCount = PhaseWeight.download
			progressSummarizer.update()
			beginCompressArchive(with: [])
			return
		}

		ZipDebugLogging.log("ZipOperationHUD.downloadArchivePlan: waiting for \(plan.fileEntries.count) file(s)")
		updatePhaseMessage(HCL10n.ZipAction.Progress.downloading)

		let totalFiles = plan.fileEntries.count
		let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
			guard let self = self, let core = self.core else {
				timer.invalidate()
				return
			}

			let downloadedCount = plan.fileEntries.filter { entry in
				let item = ZipArchiveService.resolvedItemForDownload(entry.item, core: core)
				return core.localCopy(of: item) != nil
			}.count

			if totalFiles > 0 {
				self.downloadPhase.completedUnitCount = PhaseWeight.download * Int64(downloadedCount) / Int64(totalFiles)
				self.progressSummarizer.setNeedsUpdate()
			}
		}

		ZipArchiveService.downloadArchiveEntries(plan, core: core!) { [weak self] result in
			progressTimer.invalidate()

			guard let self = self, !self.cancelled else { return }

			switch result {
			case .failure(let error):
				ZipDebugLogging.log(error: error, context: "ZipOperationHUD.downloadArchivePlan")
				self.dismissWithFinish(error: error)
			case .success(let localEntries):
				if plan.fileEntries.count > 0 && localEntries.isEmpty {
					ZipDebugLogging.log("ZipOperationHUD.downloadArchivePlan: expected \(plan.fileEntries.count) file(s) but none were downloaded")
					self.dismissWithFinish(error: NSError(ocError: .internal))
					return
				}

				ZipDebugLogging.log(localEntries: localEntries, context: "ZipOperationHUD.downloadArchivePlan")
				self.downloadPhase.completedUnitCount = PhaseWeight.download
				self.progressSummarizer.update()
				self.beginCompressArchive(with: localEntries)
			}
		}
	}

	private func beginCompressArchive(with localEntries: [ZipLocalEntry]) {
		guard let core = core, !cancelled else {
			ZipDebugLogging.log("ZipOperationHUD.beginCompressArchive: aborted — cancelled")
			dismissWithFinish(error: NSError(ocError: .cancelled))
			return
		}

		guard case .compress(let items, let parentItem) = operation, let plan = archivePlan, let parentLocation = parentItem.location else {
			ZipDebugLogging.log("ZipOperationHUD.beginCompressArchive: invalid operation state")
			dismissWithFinish(error: NSError(ocError: .internal))
			return
		}

		let archiveName = ZipArchiveService.suggestedArchiveName(for: items)
		ZipDebugLogging.log("ZipOperationHUD.beginCompressArchive: suggesting name based on \(Log.mask(archiveName))")
		core.suggestUnusedNameBased(on: archiveName, at: parentLocation, isDirectory: false, using: .bracketed, filteredBy: nil, resultHandler: { [weak self] suggestedName, _ in
			OnMainThread {
				guard let self = self, !self.cancelled else { return }

				guard let suggestedName = suggestedName else {
					ZipDebugLogging.log("ZipOperationHUD.beginCompressArchive: suggestUnusedName returned nil for \(Log.mask(archiveName))")
					self.dismissWithFinish(error: NSError(ocError: .internal))
					return
				}

				ZipDebugLogging.log("ZipOperationHUD.beginCompressArchive: using suggested name \(Log.mask(suggestedName))")
				self.performCompress(plan: plan, localEntries: localEntries, suggestedName: suggestedName, parentItem: parentItem)
			}
		})
	}

	private func performCompress(plan: ZipArchivePlan, localEntries: [ZipLocalEntry], suggestedName: String, parentItem: OCItem) {
		guard !cancelled else {
			ZipDebugLogging.log("ZipOperationHUD.performCompress: aborted — cancelled")
			return
		}

		updatePhaseMessage(HCL10n.ZipAction.Progress.compressing)

		let archiveURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent("compress-\(UUID().uuidString).zip", isDirectory: false)
		let stagingURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent("zip-staging-\(UUID().uuidString)", isDirectory: true)
		ZipDebugLogging.log(url: archiveURL, context: "ZipOperationHUD.performCompress.archiveURL")
		ZipDebugLogging.log(url: stagingURL, context: "ZipOperationHUD.performCompress.stagingURL")
		ZipDebugLogging.log(item: parentItem, context: "ZipOperationHUD.performCompress.parentItem")
		let archiveProgress = Progress(totalUnitCount: 1, parent: archivePhase, pendingUnitCount: PhaseWeight.archive)
		activeProgresses.append(archiveProgress)

		let archiveProgressObservation = archiveProgress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] _, _ in
			self?.progressSummarizer.setNeedsUpdate()
		}
		progressObservations.append(archiveProgressObservation)

		OnBackgroundQueue { [weak self] in
			guard let self = self else { return }

			do {
				try ZipArchiveService.stageArchive(plan: plan, localEntries: localEntries, at: stagingURL, progress: archiveProgress)
				try ZipArchiveService.createArchive(at: archiveURL, fromStagingDirectory: stagingURL, progress: archiveProgress)
				try? FileManager.default.removeItem(at: stagingURL)

				OnMainThread {
					guard !self.cancelled else {
						ZipDebugLogging.log("ZipOperationHUD.performCompress: cancelled after compress — cleaning up \(Log.mask(archiveURL.path))")
						try? FileManager.default.removeItem(at: archiveURL)
						return
					}

					ZipDebugLogging.log(url: archiveURL, context: "ZipOperationHUD.performCompress.archiveURL(after)")
					ZipDebugLogging.log("ZipOperationHUD.performCompress: compress succeeded — handing off to upload as \(Log.mask(suggestedName))")
					self.archivePhase.completedUnitCount = PhaseWeight.archive
					self.progressSummarizer.update()
					let result = ZipOperationResult(kind: .compress(archiveURL: archiveURL, fileName: suggestedName, parentItem: parentItem))
					self.dismissWithFinish(error: nil, result: result)
				}
			} catch {
				ZipDebugLogging.log(error: error, context: "ZipOperationHUD.performCompress")
				try? FileManager.default.removeItem(at: stagingURL)
				try? FileManager.default.removeItem(at: archiveURL)
				OnMainThread { [weak self] in
					self?.dismissWithFinish(error: error)
				}
			}
		}
	}

	private func performDecompress(archiveURL: URL, parentItem: OCItem) {
		guard !cancelled else {
			ZipDebugLogging.log("ZipOperationHUD.performDecompress: aborted — cancelled")
			return
		}

		updatePhaseMessage(HCL10n.ZipAction.Progress.decompressing)

		let extractURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
			.appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)
		ZipDebugLogging.log(url: archiveURL, context: "ZipOperationHUD.performDecompress.archiveURL")
		ZipDebugLogging.log(url: extractURL, context: "ZipOperationHUD.performDecompress.extractURL")
		ZipDebugLogging.log(item: parentItem, context: "ZipOperationHUD.performDecompress.parentItem")
		let archiveProgress = Progress(totalUnitCount: 1, parent: archivePhase, pendingUnitCount: PhaseWeight.archive)
		activeProgresses.append(archiveProgress)

		let archiveProgressObservation = archiveProgress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] _, _ in
			self?.progressSummarizer.setNeedsUpdate()
		}
		progressObservations.append(archiveProgressObservation)

		OnBackgroundQueue { [weak self] in
			guard let self = self else { return }

			do {
				try ZipArchiveService.extractArchive(at: archiveURL, to: extractURL, progress: archiveProgress)

				OnMainThread {
					guard !self.cancelled else {
						ZipDebugLogging.log("ZipOperationHUD.performDecompress: cancelled after extract — cleaning up \(Log.mask(extractURL.path))")
						try? FileManager.default.removeItem(at: extractURL)
						return
					}

					ZipDebugLogging.log(url: extractURL, context: "ZipOperationHUD.performDecompress.extractURL(afterExtract)")
					ZipDebugLogging.log("ZipOperationHUD.performDecompress: extract succeeded — handing off to upload")
					self.archivePhase.completedUnitCount = PhaseWeight.archive
					self.progressSummarizer.update()
					let result = ZipOperationResult(kind: .decompress(extractURL: extractURL, parentItem: parentItem))
					self.dismissWithFinish(error: nil, result: result)
				}
			} catch {
				ZipDebugLogging.log(error: error, context: "ZipOperationHUD.performDecompress.extractArchive")
				try? FileManager.default.removeItem(at: extractURL)
				OnMainThread { [weak self] in
					self?.dismissWithFinish(error: error)
				}
			}
		}
	}

	private func bridge(_ source: Progress, into target: Progress) {
		activeProgresses.append(source)

		let observation = source.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] observedProgress, _ in
			target.completedUnitCount = Int64(Double(target.totalUnitCount) * observedProgress.fractionCompleted)
			self?.progressSummarizer.setNeedsUpdate()
		}
		progressObservations.append(observation)
	}

	private func updatePhaseMessage(_ message: String) {
		onMain {
			self.overallProgress.localizedDescription = message
			self.messageLabel.text = message
			self.progressSummarizer.update()
		}
	}

	private func finish(error: Error?, result: ZipOperationResult?) {
		if let error = error {
			ZipDebugLogging.log(error: error, context: "ZipOperationHUD.finish")
		} else if let result = result {
			switch result.kind {
			case .compress(let archiveURL, let fileName, _):
				ZipDebugLogging.log("ZipOperationHUD.finish: compress succeeded archive=\(Log.mask(archiveURL.path)) fileName=\(Log.mask(fileName))")
			case .decompress(let extractURL, _):
				ZipDebugLogging.log(url: extractURL, context: "ZipOperationHUD.finish.decompress")
			}
		} else {
			ZipDebugLogging.log("ZipOperationHUD.finish: completed with no error and no result")
		}

		progressSummarizer.stopTracking(progress: overallProgress)
		completion?(error, result)
		completion = nil
	}

	override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		messageLabel.applyThemeCollection(collection)
		super.applyThemeCollection(theme: theme, collection: collection, event: event)
	}
}
