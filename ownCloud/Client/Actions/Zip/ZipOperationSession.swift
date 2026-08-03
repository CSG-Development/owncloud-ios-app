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

	private let overallProgress = Progress(totalUnitCount: 1000)
	private var progressObservations: [NSKeyValueObservation] = []
	private var activeProgresses: [Progress] = []
	private var importProgresses: [Progress] = []
	private var cancelled = false
	private var archivePlan: ZipArchivePlan?

	private var downloadFraction: Double = 0
	private var archiveFraction: Double = 0
	private var isImporting = false
	private var statusMessage: String = HCL10n.ZipAction.Progress.preparing
	private var displayTimer: Timer?
	private var downloadWatchdog: DispatchSourceTimer?
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
		downloadWatchdog?.cancel()
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
		for progress in importProgresses {
			progress.cancel()
		}
		overallProgress.cancel()
		finish(error: NSError(ocError: .cancelled), notifyCoordinator: false)
	}

	func registerImportProgress(_ progress: Progress) {
		importProgresses.append(progress)
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
				OnMainThread {
					guard let self = self, !self.cancelled else { return }
					switch result {
					case .failure(let error):
						self.finish(error: error)
					case .success(let plan):
						self.archivePlan = plan
						self.materializeArchivePlan(plan)
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

		updatePhaseMessage(HCL10n.ZipAction.Progress.downloading, phase: .downloading)

		let token = ZipArchiveService.ZipDownloadCancellationToken()
		downloadCancellationToken = token
		startDownloadWatchdog()

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
				self.stopDownloadWatchdog()
				self.downloadCancellationToken = nil
				self.trackedDownloadProgress = nil
				guard !self.cancelled else { return }

				switch result {
				case .failure(let error):
					self.finish(error: error)
				case .success(let archiveURL):
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

		coordinator?.sessionDidPreparePlan(self, alreadyLocalItemLocalIDs: ZipArchiveService.alreadyLocalItemLocalIDs(in: plan, core: core))

		updatePhaseMessage(HCL10n.ZipAction.Progress.downloading, phase: .downloading)

		let token = ZipArchiveService.ZipDownloadCancellationToken()
		downloadCancellationToken = token
		let already = coordinator?.sessionMaterializedRelativePaths(self) ?? []
		startDownloadWatchdog()

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
				self.stopDownloadWatchdog()
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
		let stagingURL = workingDirectoryURL.appendingPathComponent("zip-staging-\(UUID().uuidString)", isDirectory: true)
		let archiveProgress = Progress(totalUnitCount: 1)
		activeProgresses.append(archiveProgress)
		bridge(archiveProgress) { [weak self] fraction in
			self?.setArchiveFraction(fraction)
		}

		DispatchQueue.global(qos: .background).async { [weak self] in
			guard let self = self else { return }

			// Log fraction every 10 s so the console shows the operation is alive
			// even when ZIPFoundation's zipItem call holds the thread without callbacks.
			let jobID = self.jobID
			let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .background))
			watchdog.schedule(deadline: .now() + 10, repeating: 10)
			watchdog.setEventHandler { [weak archiveProgress] in
				let frac = archiveProgress?.fractionCompleted ?? 0
				ZipDebugLogging.log("compress[\(jobID)] still running: \(String(format: "%.1f%%", frac * 100))")
			}
			watchdog.resume()
			defer { watchdog.cancel() }

			do {
				if self.cancelled || archiveProgress.isCancelled {
					throw NSError(ocError: .cancelled)
				}
				try ZipArchiveService.stageArchive(plan: plan, localEntries: localEntries, at: stagingURL, progress: archiveProgress)
				if self.cancelled || archiveProgress.isCancelled {
					throw NSError(ocError: .cancelled)
				}
				try ZipArchiveService.createArchive(at: archiveURL, fromStagingDirectory: stagingURL, progress: archiveProgress)
				try? FileManager.default.removeItem(at: stagingURL)

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
				try? FileManager.default.removeItem(at: stagingURL)
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

			// Log fraction every 10 s so the console shows the operation is alive
			// even when a single large entry dominates extraction time.
			let jobID = self.jobID
			let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .background))
			watchdog.schedule(deadline: .now() + 10, repeating: 10)
			watchdog.setEventHandler { [weak archiveProgress] in
				let frac = archiveProgress?.fractionCompleted ?? 0
				ZipDebugLogging.log("decompress[\(jobID)] still running: \(String(format: "%.1f%%", frac * 100))")
			}
			watchdog.resume()
			defer { watchdog.cancel() }

			do {
				try ZipArchiveService.extractArchive(at: archiveURL, to: extractURL, progress: archiveProgress)

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
		overallProgress.localizedDescription = message
		publishDisplayProgress(phase: phase)
	}

	private func startDownloadWatchdog() {
		let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .background))
		watchdog.schedule(deadline: .now() + 10, repeating: 10)
		let jobID = self.jobID
		watchdog.setEventHandler { [weak self] in
			guard let self else { return }
			// completedUnitCount / totalUnitCount are Int64 written only on the main
			// thread; reading them here is safe on ARM64 (aligned 64-bit loads are atomic).
			let completed = self.trackedDownloadProgress?.completedUnitCount ?? 0
			let total = self.trackedDownloadProgress?.totalUnitCount ?? 0
			let totalStr = total > 0 ? "\(total)" : "?"
			ZipDebugLogging.log("download[\(jobID)] still running: \(completed) / \(totalStr) bytes")
		}
		watchdog.resume()
		downloadWatchdog = watchdog
	}

	private func stopDownloadWatchdog() {
		downloadWatchdog?.cancel()
		downloadWatchdog = nil
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

	private func finish(error: Error?, result: ZipOperationResult? = nil, notifyCoordinator: Bool = true) {
		stopDisplayTimer()

		let completion = self.completion
		self.completion = nil
		completion?(error, result)
	}
}
