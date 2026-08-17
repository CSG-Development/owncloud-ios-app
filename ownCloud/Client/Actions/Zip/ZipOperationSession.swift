import Foundation
import ownCloudSDK
import ownCloudAppShared

struct ZipOperationResult {
	enum Kind {
		case compress(archiveURL: URL, fileName: String, parentItem: OCItem)
		case decompress(extractURL: URL, parentItem: OCItem)
	}

	let kind: Kind
}

typealias ZipOperationSessionCompletionHandler = (Error?, ZipOperationResult?) -> Void

/// Runs compress/decompress work and publishes progress into `ZipOperationCenter` via coordinator.
/// Progress covers materialize + archive/extract only; vault import is owned by the coordinator.
final class ZipOperationSession {
	enum Operation {
		case compress(items: [OCItem], parentItem: OCItem)
		case decompress(zipItem: OCItem, parentItem: OCItem)
	}

	private enum DisplayWeight {
		static let download = 0.55
		static let archive = 0.35
		static let preImportCeiling = 0.9
	}

	let jobID: String
	private let operation: Operation
	private weak var core: OCCore?
	private weak var coordinator: ZipOperationCoordinator?
	private var completion: ZipOperationSessionCompletionHandler?
	private let workingDirectoryURL: URL
	private let downloadsDirectoryURL: URL

	private var progressObservations: [NSKeyValueObservation] = []
	private var activeProgresses: [Progress] = []
	private var cancelled = false
	private var archivePlan: ZipArchivePlan?

	private var downloadFraction: Double = 0
	private var archiveFraction: Double = 0
	private var isImporting = false
	private var statusMessage: String = HCL10n.ZipAction.Progress.preparing
	private var displayTimer: Timer?
	private weak var trackedDownloadProgress: Progress?
	private var downloadCancellationToken: ZipArchiveService.ZipDownloadCancellationToken?
	private var lastPublishedFraction: Double = -1
	private var lastPublishedAt: Date = .distantPast
	private var lastPublishedPhase: ZipOperationPhase?

	init(
		core: OCCore,
		operation: Operation,
		jobID: String,
		workingDirectoryURL: URL,
		coordinator: ZipOperationCoordinator,
		completion: @escaping ZipOperationSessionCompletionHandler
	) {
		self.core = core
		self.operation = operation
		self.jobID = jobID
		self.workingDirectoryURL = workingDirectoryURL
		self.downloadsDirectoryURL = workingDirectoryURL.appendingPathComponent("downloads", isDirectory: true)
		self.coordinator = coordinator
		self.completion = completion
	}

	deinit {
		displayTimer?.invalidate()
		progressObservations.removeAll()
	}

	func start() {
		startDisplayTimer()
		if statusMessage == HCL10n.ZipAction.Progress.preparing, downloadFraction == 0, archiveFraction == 0, !isImporting {
			publishDisplayProgress(phase: .preparing)
		} else {
			publishDisplayProgress(phase: nil)
		}
		beginMaterialize()
	}

	/// Restore persisted UI state when resuming after relaunch.
	func restore(status: String, fractionCompleted: Double, phase: ZipOperationPhase) {
		statusMessage = status.isEmpty ? statusMessage : status
		switch phase {
		case .importing:
			isImporting = true
			downloadFraction = 1
			archiveFraction = 1
		case .archiving:
			downloadFraction = 1
			archiveFraction = max(0, min(1, (fractionCompleted - DisplayWeight.download) / max(DisplayWeight.archive, 0.0001)))
		case .downloading:
			downloadFraction = max(0, min(1, fractionCompleted / max(DisplayWeight.preImportCeiling, 0.0001)))
			archiveFraction = 0
		case .preparing, .failed, .completed:
			break
		}
		coordinator?.sessionDidUpdate(self, status: statusMessage, fraction: fractionCompleted, phase: phase)
	}

	/// Cancel invoked by coordinator (import already cancelled there).
	func cancelFromCoordinator() {
		cancelled = true
		downloadCancellationToken?.cancel()
		downloadCancellationToken = nil
		for progress in activeProgresses {
			progress.cancel()
		}
		finish(error: NSError(ocError: .cancelled))
	}

	func registerImportProgress(_ progress: Progress) {
		activeProgresses.append(progress)
	}

	func beginImportPhase() {
		OnMainThread {
			self.isImporting = true
			self.statusMessage = HCL10n.ZipAction.Progress.importing
			self.publishDisplayProgress(phase: .importing)
		}
	}

	func updateImportProgress(_ progress: Progress) {
		OnMainThread {
			self.isImporting = true
			self.statusMessage = HCL10n.ZipAction.Progress.importing
			let fraction = DisplayWeight.preImportCeiling + (progress.fractionCompleted * (1.0 - DisplayWeight.preImportCeiling))
			self.coordinator?.sessionDidUpdate(self, status: self.statusMessage, fraction: fraction, phase: .importing)
		}
	}

	// MARK: - Pipeline

	private func beginMaterialize() {
		guard let core = core, !cancelled else {
			finish(error: NSError(ocError: .internal))
			return
		}

		try? FileManager.default.createDirectory(at: downloadsDirectoryURL, withIntermediateDirectories: true)

		switch operation {
		case .compress(let selectedItems, _):
			ZipArchiveService.collectArchivePlan(for: selectedItems, core: core) { [weak self] result in
				// Run space check on whatever queue plan completion uses, then hop to main for UI.
				guard let self = self, !self.cancelled else { return }
				switch result {
				case .failure(let error):
					OnMainThread { self.finish(error: error) }
				case .success(let plan):
					self.archivePlan = plan
					let already = self.coordinator?.sessionMaterializedRelativePaths(self) ?? []
					do {
						let required = ZipArchiveService.requiredFreeSpaceForCompress(
							plan: plan,
							downloadsDirectory: self.downloadsDirectoryURL,
							alreadyMaterializedRelativePaths: already
						)
						try ZipArchiveService.ensureEnoughDiskSpace(requiredBytes: required, at: self.workingDirectoryURL)
					} catch {
						OnMainThread { self.finish(error: error) }
						return
					}
					OnMainThread {
						guard !self.cancelled else { return }
						self.coordinator?.sessionClaimItems(self, items: plan.affectedItems) { [weak self] in
							OnMainThread {
								guard let self, !self.cancelled else { return }
								self.materializeArchivePlan(plan)
							}
						}
					}
				}
			}

		case .decompress(let zipItem, let parentItem):
			materializeZipItem(zipItem, parentItem: parentItem)
		}
	}

	private func materializeZipItem(_ zipItem: OCItem, parentItem: OCItem) {
		guard let core = core, !cancelled else {
			finish(error: NSError(ocError: .internal))
			return
		}

		let fileName = zipItem.name ?? "archive.zip"
		let destinationURL = downloadsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
		let already = coordinator?.sessionMaterializedRelativePaths(self) ?? []
		// Only skip download budget when the zip is already in the job downloads dir.
		// Vault-local copies still need space to copy into downloads.
		let expectedZipSize = Int64(max(zipItem.size, 0))
		let zipAlreadyOnDisk = ZipArchiveService.fileIsComplete(at: destinationURL, expectedSize: expectedZipSize)
		ZipArchiveService.removeItemIfExists(at: ZipArchiveService.partURL(for: destinationURL))
		if !zipAlreadyOnDisk {
			ZipArchiveService.removeItemIfExists(at: destinationURL)
		}

		do {
			let required = ZipArchiveService.requiredFreeSpaceForDecompressDownload(
				zipByteSize: Int64(max(zipItem.size, 0)),
				zipAlreadyOnDisk: zipAlreadyOnDisk
			)
			try ZipArchiveService.ensureEnoughDiskSpace(requiredBytes: required, at: workingDirectoryURL)
		} catch {
			finish(error: error)
			return
		}

		updatePhaseMessage(HCL10n.ZipAction.Progress.downloading, phase: .downloading)

		let claimProfile = ZipDebugLogging.ProfileScope("decompress.claim", extra: "job=\(jobID)")
		coordinator?.sessionClaimItems(self, items: [zipItem, parentItem]) { [weak self] in
			claimProfile.end()
			OnMainThread {
				guard let self, !self.cancelled else { return }
				self.startZipDownload(zipItem: zipItem, parentItem: parentItem, destinationURL: destinationURL, fileName: fileName, already: already)
			}
		}
	}

	private func startZipDownload(zipItem: OCItem, parentItem: OCItem, destinationURL: URL, fileName: String, already: Set<String>) {
		guard let core = core, !cancelled else {
			finish(error: NSError(ocError: .internal))
			return
		}

		let token = ZipArchiveService.ZipDownloadCancellationToken()
		downloadCancellationToken = token
		let downloadProfile = ZipDebugLogging.ProfileScope(
			"decompress.download",
			extra: "job=\(jobID) size=\(ZipDebugLogging.formattedBytes(Int64(max(zipItem.size, 0))))"
		)

		_ = ZipArchiveService.materializeItem(
			zipItem,
			core: core,
			to: destinationURL,
			alreadyMaterializedRelativePaths: already,
			publishProgress: { [weak self] progress in
				guard let self else { return }
				self.activeProgresses.append(progress)
				self.trackedDownloadProgress = progress
				self.bridge(progress) { [weak self] fraction in
					self?.setDownloadFraction(max(self?.downloadFraction ?? 0, fraction))
				}
			},
			cancellationToken: token
		) { [weak self] result in
			OnMainThread {
				guard let self else { return }
				self.downloadCancellationToken = nil
				self.trackedDownloadProgress = nil
				guard !self.cancelled else {
					downloadProfile.end(extra: "cancelled")
					return
				}

				switch result {
				case .failure(let error):
					downloadProfile.end(extra: "failed")
					self.finish(error: error)
				case .success(let archiveURL):
					downloadProfile.end(extra: "ok")
					self.coordinator?.sessionDidMaterialize(self, relativePath: fileName)
					self.setDownloadFraction(1)
					self.performDecompress(archiveURL: archiveURL, parentItem: parentItem)
				}
			}
		}
	}

	private func materializeArchivePlan(_ plan: ZipArchivePlan) {
		guard let core = core, !cancelled else {
			finish(error: NSError(ocError: .internal))
			return
		}

		if plan.fileEntries.isEmpty {
			setDownloadFraction(1)
			beginCompressArchive(with: [])
			return
		}

		updatePhaseMessage(HCL10n.ZipAction.Progress.downloading, phase: .downloading)

		let token = ZipArchiveService.ZipDownloadCancellationToken()
		downloadCancellationToken = token
		let already = coordinator?.sessionMaterializedRelativePaths(self) ?? []

		_ = ZipArchiveService.materializeArchiveEntries(
			plan,
			core: core,
			into: downloadsDirectoryURL,
			alreadyMaterializedRelativePaths: already,
			publishProgress: { [weak self] progress in
				guard let self else { return }
				self.activeProgresses.append(progress)
				self.trackedDownloadProgress = progress
				self.bridge(progress) { [weak self] fraction in
					self?.setDownloadFraction(max(self?.downloadFraction ?? 0, fraction))
				}
			},
			onEntryMaterialized: { [weak self] relativePath in
				guard let self, !self.cancelled else { return }
				self.coordinator?.sessionDidMaterialize(self, relativePath: relativePath)
			},
			cancellationToken: token
		) { [weak self] result in
			OnMainThread {
				guard let self = self else { return }
				self.downloadCancellationToken = nil
				self.trackedDownloadProgress = nil
				guard !self.cancelled else { return }

				switch result {
				case .failure(let error):
					self.finish(error: error)
				case .success(let localEntries):
					if plan.fileEntries.count > 0 && localEntries.isEmpty {
						self.finish(error: NSError(ocError: .internal))
						return
					}
					self.setDownloadFraction(1)
					self.beginCompressArchive(with: localEntries)
				}
			}
		}
	}

	private func beginCompressArchive(with localEntries: [ZipLocalEntry]) {
		guard let core = core, !cancelled else {
			finish(error: NSError(ocError: .cancelled))
			return
		}

		guard case .compress(let items, let parentItem) = operation, let plan = archivePlan, let parentLocation = parentItem.location else {
			finish(error: NSError(ocError: .internal))
			return
		}

		let archiveName = ZipArchiveService.suggestedArchiveName(for: items)
		core.suggestUnusedNameBased(on: archiveName, at: parentLocation, isDirectory: false, using: .bracketed, filteredBy: nil, resultHandler: { [weak self] suggestedName, _ in
			OnMainThread {
				guard let self = self, !self.cancelled else { return }
				guard let suggestedName = suggestedName else {
					self.finish(error: NSError(ocError: .internal))
					return
				}
				self.performCompress(plan: plan, localEntries: localEntries, suggestedName: suggestedName, parentItem: parentItem)
			}
		})
	}

	private func performCompress(plan: ZipArchivePlan, localEntries: [ZipLocalEntry], suggestedName: String, parentItem: OCItem) {
		guard !cancelled else { return }

		updatePhaseMessage(HCL10n.ZipAction.Progress.compressing, phase: .archiving)

		let archiveURL = workingDirectoryURL.appendingPathComponent("compress-\(UUID().uuidString).zip", isDirectory: false)
		let archiveProgress = Progress(totalUnitCount: 1)
		activeProgresses.append(archiveProgress)
		bridge(archiveProgress) { [weak self] fraction in
			self?.setArchiveFraction(fraction)
		}

		DispatchQueue.global(qos: .background).async { [weak self] in
			guard let self = self else { return }

			do {
				if self.cancelled || archiveProgress.isCancelled {
					throw NSError(ocError: .cancelled)
				}
				try ZipArchiveService.prepareZipRoot(
					plan: plan,
					localEntries: localEntries,
					at: self.downloadsDirectoryURL,
					progress: archiveProgress
				)
				if self.cancelled || archiveProgress.isCancelled {
					throw NSError(ocError: .cancelled)
				}
				try ZipArchiveService.createArchive(
					at: archiveURL,
					fromDirectory: self.downloadsDirectoryURL,
					progress: archiveProgress
				)

				OnMainThread {
					guard !self.cancelled else {
						try? FileManager.default.removeItem(at: archiveURL)
						return
					}
					self.setArchiveFraction(1)
					let result = ZipOperationResult(kind: .compress(archiveURL: archiveURL, fileName: suggestedName, parentItem: parentItem))
					self.finish(error: nil, result: result)
				}
			} catch {
				try? FileManager.default.removeItem(at: archiveURL)
				OnMainThread { [weak self] in
					self?.finish(error: error)
				}
			}
		}
	}

	private func performDecompress(archiveURL: URL, parentItem: OCItem) {
		guard !cancelled else { return }

		updatePhaseMessage(HCL10n.ZipAction.Progress.decompressing, phase: .archiving)

		let extractURL = workingDirectoryURL.appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)
		let archiveProgress = Progress(totalUnitCount: 1)
		activeProgresses.append(archiveProgress)
		bridge(archiveProgress) { [weak self] fraction in
			self?.setArchiveFraction(fraction)
		}

		DispatchQueue.global(qos: .background).async { [weak self] in
			guard let self = self else { return }

			let extractProfile = ZipDebugLogging.ProfileScope(
				"decompress.extract",
				extra: "job=\(self.jobID) archive=\(Log.mask(archiveURL.lastPathComponent))"
			)

			do {
				try ZipArchiveService.extractArchive(at: archiveURL, to: extractURL, progress: archiveProgress)
				extractProfile.end(extra: "ok")

				OnMainThread {
					guard !self.cancelled else {
						try? FileManager.default.removeItem(at: extractURL)
						return
					}
					self.setArchiveFraction(1)
					let result = ZipOperationResult(kind: .decompress(extractURL: extractURL, parentItem: parentItem))
					self.finish(error: nil, result: result)
				}
			} catch {
				extractProfile.end(extra: "failed")
				try? FileManager.default.removeItem(at: extractURL)
				OnMainThread { [weak self] in
					self?.finish(error: error)
				}
			}
		}
	}

	// MARK: - Progress

	private static func fraction(of source: Progress) -> Double {
		if source.totalUnitCount > 0 {
			return min(1, max(0, Double(source.completedUnitCount) / Double(source.totalUnitCount)))
		}
		return min(1, max(0, source.fractionCompleted))
	}

	private func bridge(_ source: Progress, onFraction: @escaping (Double) -> Void) {
		let publish = { [weak source] in
			guard let source else { return }
			let fraction = Self.fraction(of: source)
			// KVO can fire on any thread. Ensure the fraction handler (which mutates
			// stored properties) always runs on the main thread to eliminate data races.
			OnMainThread(inline: true) { onFraction(fraction) }
		}
		progressObservations.append(source.observe(\.fractionCompleted, options: [.initial, .new]) { _, _ in publish() })
		progressObservations.append(source.observe(\.completedUnitCount, options: [.new]) { _, _ in publish() })
		progressObservations.append(source.observe(\.totalUnitCount, options: [.new]) { _, _ in publish() })
	}

	private func setDownloadFraction(_ value: Double) {
		downloadFraction = min(1, max(0, value))
		publishDisplayProgress(phase: .downloading)
	}

	private func setArchiveFraction(_ value: Double) {
		archiveFraction = min(1, max(0, value))
		publishDisplayProgress(phase: .archiving)
	}

	private func updatePhaseMessage(_ message: String, phase: ZipOperationPhase) {
		statusMessage = message
		publishDisplayProgress(phase: phase)
	}

	private func startDisplayTimer() {
		displayTimer?.invalidate()
		let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
			guard let self else { return }
			if let tracked = self.trackedDownloadProgress, self.downloadFraction < 1, !self.isImporting {
				self.setDownloadFraction(max(self.downloadFraction, Self.fraction(of: tracked)))
			} else {
				self.publishDisplayProgress(phase: nil)
			}
		}
		RunLoop.main.add(timer, forMode: .common)
		displayTimer = timer
	}

	private func stopDisplayTimer() {
		displayTimer?.invalidate()
		displayTimer = nil
	}

	private func preImportFraction() -> Double {
		if archiveFraction <= 0 {
			return downloadFraction * DisplayWeight.preImportCeiling
		}
		return downloadFraction * DisplayWeight.download + archiveFraction * DisplayWeight.archive
	}

	private func publishDisplayProgress(phase: ZipOperationPhase?) {
		OnMainThread {
			let fraction: Double
			if self.isImporting {
				fraction = max(self.preImportFraction(), DisplayWeight.preImportCeiling)
			} else {
				fraction = self.preImportFraction()
			}

			let now = Date()
			let phaseChanged = phase != nil && phase != self.lastPublishedPhase
			let fractionMoved = abs(fraction - self.lastPublishedFraction) >= 0.01
			let timedOut = now.timeIntervalSince(self.lastPublishedAt) >= 0.2
			guard phaseChanged || fractionMoved || timedOut || fraction >= 1.0 || fraction <= 0 else {
				return
			}

			self.lastPublishedFraction = fraction
			self.lastPublishedAt = now
			if let phase {
				self.lastPublishedPhase = phase
			}
			self.coordinator?.sessionDidUpdate(self, status: self.statusMessage, fraction: fraction, phase: phase)
		}
	}

	private func finish(error: Error?, result: ZipOperationResult? = nil) {
		stopDisplayTimer()

		let completion = self.completion
		self.completion = nil
		completion?(error, result)
	}
}
