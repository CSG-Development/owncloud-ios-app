import UIKit
import ownCloudSDK
import ownCloudAppShared

/// Owns zip job persistence, background execution, cancel cleanup, and resume across launches.
/// Job completes when vault placeholders are created; server upload is handled by normal sync.
final class ZipOperationCoordinator {
	static let shared = ZipOperationCoordinator()

	private final class ActiveRun {
		let job: ZipOperationJob
		let record: ZipOperationRecord
		var session: ZipOperationSession?
		var importProgresses: [Progress] = []
		var importObservations: [NSKeyValueObservation] = []
		var backgroundTask: OCBackgroundTask?
		weak var core: OCCore?
		weak var hostViewController: UIViewController?
		var isCancelling = false
		var lastPersistedAt: Date = .distantPast
		var lastPersistedPhase: ZipOperationPhase?

		init(job: ZipOperationJob, record: ZipOperationRecord) {
			self.job = job
			self.record = record
			self.lastPersistedPhase = job.phase
		}
	}

	private let lock = NSLock()
	private var activeRunsByID: [String: ActiveRun] = [:]

	private init() {}

	// MARK: - Start

	func startCompress(items: [OCItem], parentItem: OCItem, core: OCCore, hostViewController: UIViewController?) {
		let bookmarkUUID = core.bookmark.uuid
		let alreadyLocal = Set(items.compactMap { item -> String? in
			guard let localID = item.localID as String? else { return nil }
			return ZipArchiveService.localFileURL(for: item, core: core) != nil ? localID : nil
		})

		let parentLocation = location(for: parentItem, bookmarkUUID: bookmarkUUID)
		let job = ZipOperationJob(
			kind: .compress,
			bookmarkUUID: bookmarkUUID,
			documentName: ZipArchiveService.suggestedArchiveName(for: items),
			parentLocationKey: ZipOperationRecord.locationKey(for: parentLocation) ?? "",
			parentItemLocalID: parentItem.localID as String?,
			sourceItemLocalIDs: items.compactMap { $0.localID as String? },
			alreadyLocalItemLocalIDs: Array(alreadyLocal)
		)

		begin(job: job, core: core, hostViewController: hostViewController, operation: .compress(items: items, parentItem: parentItem))
	}

	func startDecompress(zipItem: OCItem, parentItem: OCItem, core: OCCore, hostViewController: UIViewController?) {
		let bookmarkUUID = core.bookmark.uuid
		let alreadyLocal: [String] = {
			guard let localID = zipItem.localID as String?,
			      ZipArchiveService.localFileURL(for: zipItem, core: core) != nil else { return [] }
			return [localID]
		}()

		let parentLocation = location(for: parentItem, bookmarkUUID: bookmarkUUID)
		let job = ZipOperationJob(
			kind: .decompress,
			bookmarkUUID: bookmarkUUID,
			documentName: zipItem.name ?? HCL10n.ZipAction.defaultArchiveName,
			parentLocationKey: ZipOperationRecord.locationKey(for: parentLocation) ?? "",
			parentItemLocalID: parentItem.localID as String?,
			zipItemLocalID: zipItem.localID as String?,
			alreadyLocalItemLocalIDs: alreadyLocal
		)

		begin(job: job, core: core, hostViewController: hostViewController, operation: .decompress(zipItem: zipItem, parentItem: parentItem))
	}

	// MARK: - Resume

	func resumePendingJobs() {
		rehydrateUIFromStore()

		for bookmark in OCBookmarkManager.shared.bookmarks {
			let resumable = bookmark.zipOperationStore.resumableJobs
			guard !resumable.isEmpty else { continue }

			OCCoreManager.shared.requestCore(for: bookmark, setup: nil) { [weak self] core, error in
				guard let self, let core, error == nil else { return }
				DispatchQueue.global(qos: .userInitiated).async {
					for job in resumable {
						let operation = self.operation(for: job, core: core)
						OnMainThread {
							self.resume(job: job, core: core, preresolvedOperation: operation)
						}
					}
				}
			}
		}
	}

	/// Publish incomplete, non-failed jobs into the in-memory UI center before cores finish starting.
	func rehydrateUIFromStore() {
		for bookmark in OCBookmarkManager.shared.bookmarks {
			for job in bookmark.zipOperationStore.incompleteJobs {
				if job.phase == .failed {
					// Failed jobs are not shown until the user retries; drop stale ones across launches.
					job.removeWorkingDirectory()
					bookmark.removeZipJob(id: job.id)
					ZipOperationCenter.shared.remove(id: job.id)
					continue
				}
				publishRecord(for: job)
			}
		}
	}

	private func resume(job: ZipOperationJob, core: OCCore, preresolvedOperation: ZipOperationSession.Operation? = nil) {
		lock.lock()
		let alreadyActive = activeRunsByID[job.id] != nil
		lock.unlock()
		guard !alreadyActive, job.phase != .completed else { return }

		job.attemptCount += 1
		if job.phase == .failed {
			if job.kind == .compress {
				if job.uploadPlaceholderLocalID != nil {
					// Placeholder already queued — sync owns the rest.
					job.phase = .importing
					job.statusText = HCL10n.ZipAction.Progress.importing
				} else if job.archiveURL.map({ FileManager.default.fileExists(atPath: $0.path) }) ?? false {
					job.phase = .importing
					job.statusText = HCL10n.ZipAction.Progress.importing
				} else {
					job.phase = .preparing
					job.statusText = HCL10n.ZipAction.Progress.preparing
					job.fractionCompleted = 0
				}
			} else if job.kind == .decompress {
				if FileManager.default.fileExists(atPath: job.extractDirectoryURL.path) {
					job.phase = .importing
					job.statusText = HCL10n.ZipAction.Progress.importing
				} else if !job.uploadedFileLocalIDs.isEmpty || !job.createdFolderLocalIDs.isEmpty {
					job.phase = .importing
					job.statusText = HCL10n.ZipAction.Progress.importing
				} else {
					job.phase = .preparing
					job.statusText = HCL10n.ZipAction.Progress.preparing
					job.fractionCompleted = 0
				}
			}
			job.lastErrorDescription = nil
		}
		persist(job, core: core)
		publishRecord(for: job)

		ZipDebugLogging.log("ZipOperationCoordinator.resume: id=\(job.id) phase=\(job.phase.rawValue) attempt=\(job.attemptCount)")

		guard let operation = preresolvedOperation ?? operation(for: job, core: core) else {
			job.phase = .failed
			job.lastErrorDescription = "Missing items"
			job.statusText = job.lastErrorDescription ?? HCL10n.ZipAction.Progress.preparing
			core.bookmark.saveZipJob(job)
			ZipOperationCenter.shared.remove(id: job.id)
			ZipDebugLogging.log("ZipOperationCoordinator.resume: missing items for \(job.id)")
			return
		}

		begin(job: job, core: core, hostViewController: nil, operation: operation, isResume: true)
	}

	// MARK: - Cancel

	func cancel(jobID: String) {
		lock.lock()
		guard let run = activeRunsByID[jobID] else {
			lock.unlock()
			cancelPersistedOnly(jobID: jobID)
			return
		}
		run.isCancelling = true
		let importProgresses = run.importProgresses
		let session = run.session
		let core = run.core
		let job = run.job
		lock.unlock()

		ZipDebugLogging.log("ZipOperationCoordinator.cancel: id=\(jobID)")

		for progress in importProgresses {
			progress.cancel()
		}
		session?.cancelFromCoordinator()

		if let core {
			deleteUploadPlaceholderIfNeeded(job: job, core: core)
			deleteDecompressImportOrphans(job: job, core: core)
		}

		tearDown(jobID: jobID, purgeWorkingDirectory: true)
	}

	private func cancelPersistedOnly(jobID: String) {
		for bookmark in OCBookmarkManager.shared.bookmarks {
			guard let job = bookmark.zipOperationStore.jobsByID[jobID] else { continue }
			OCCoreManager.shared.requestCore(for: bookmark, setup: nil) { [weak self] core, _ in
				guard let self else { return }
				if let core {
					self.deleteUploadPlaceholderIfNeeded(job: job, core: core)
					self.deleteDecompressImportOrphans(job: job, core: core)
					OCCoreManager.shared.returnCore(for: bookmark, completionHandler: nil)
				}
				bookmark.removeZipJob(id: jobID)
				ZipOperationCenter.shared.remove(id: jobID)
			}
			return
		}
		ZipOperationCenter.shared.remove(id: jobID)
	}

	func retry(jobID: String) {
		for bookmark in OCBookmarkManager.shared.bookmarks {
			guard let job = bookmark.zipOperationStore.jobsByID[jobID], job.phase == .failed else { continue }
			OCCoreManager.shared.requestCore(for: bookmark, setup: nil) { [weak self] core, error in
				guard let self, let core, error == nil else { return }
				OnMainThread {
					self.resume(job: job, core: core)
				}
			}
			return
		}
	}

	// MARK: - Session hooks

	func sessionDidUpdate(_ session: ZipOperationSession, status: String, fraction: Double, phase: ZipOperationPhase?) {
		guard let run = run(for: session) else { return }
		let previousPhase = run.job.phase
		run.job.statusText = status
		run.job.fractionCompleted = fraction
		if let phase {
			run.job.phase = phase
		}
		// Avoid encoding the job store on every progress tick — that stalls the main thread.
		let phaseChanged = run.job.phase != previousPhase
		persistProgressIfNeeded(run: run, force: phaseChanged)
		ZipOperationCenter.shared.update(run.record, statusText: status, fractionCompleted: fraction)
	}

	func sessionDidPreparePlan(_ session: ZipOperationSession, alreadyLocalItemLocalIDs: [String]) {
		guard let run = run(for: session) else { return }
		var merged = Set(run.job.alreadyLocalItemLocalIDs)
		merged.formUnion(alreadyLocalItemLocalIDs)
		run.job.alreadyLocalItemLocalIDs = Array(merged)
		persist(run.job, core: run.core)
		run.lastPersistedAt = Date()
		run.lastPersistedPhase = run.job.phase
	}

	func sessionMaterializedRelativePaths(_ session: ZipOperationSession) -> Set<String> {
		guard let run = run(for: session) else { return [] }
		return Set(run.job.materializedRelativePaths)
	}

	func sessionDidMaterialize(_ session: ZipOperationSession, relativePath: String) {
		guard let run = run(for: session) else { return }
		if !run.job.materializedRelativePaths.contains(relativePath) {
			run.job.materializedRelativePaths.append(relativePath)
			persistProgressIfNeeded(run: run, force: false)
		}
	}

	/// Persist at most ~1/s during progress; always when forced (phase changes, etc.).
	private func persistProgressIfNeeded(run: ActiveRun, force: Bool) {
		let now = Date()
		guard force || now.timeIntervalSince(run.lastPersistedAt) >= 1.0 || run.job.phase != run.lastPersistedPhase else {
			return
		}
		persist(run.job, core: run.core)
		run.lastPersistedAt = now
		run.lastPersistedPhase = run.job.phase
	}

	// MARK: - Internals

	private func begin(
		job: ZipOperationJob,
		core: OCCore,
		hostViewController: UIViewController?,
		operation: ZipOperationSession.Operation,
		isResume: Bool = false
	) {
		try? job.ensureWorkingDirectory()
		persist(job, core: core)

		let record = publishRecord(for: job)

		let run = ActiveRun(job: job, record: record)
		run.core = core
		run.hostViewController = hostViewController
		run.backgroundTask = OCBackgroundTask(name: "com.owncloud.zip-operation-\(job.id)", expirationHandler: { [weak self] bgTask in
			ZipDebugLogging.log("ZipOperationCoordinator: background task expired for \(job.id)")
			self?.lock.lock()
			if let active = self?.activeRunsByID[job.id] {
				active.job.lastErrorDescription = "Interrupted"
				if active.job.phase != .importing {
					active.job.phase = .failed
					if let core = active.core {
						self?.persist(active.job, core: core)
					}
					ZipOperationCenter.shared.remove(id: active.job.id)
				} else if let core = active.core {
					self?.persist(active.job, core: core)
				}
			}
			self?.lock.unlock()
			bgTask.end()
		}).start()

		let jobID = job.id
		let session = ZipOperationSession(
			core: core,
			operation: operation,
			jobID: jobID,
			workingDirectoryURL: job.workingDirectoryURL,
			coordinator: self
		) { [weak self, weak hostViewController] error, result in
			guard let self else { return }
			self.lock.lock()
			let session = self.activeRunsByID[jobID]?.session
			self.lock.unlock()
			guard let session else { return }
			self.handleSessionCompletion(error: error, result: result, session: session, core: core, hostViewController: hostViewController)
		}

		lock.lock()
		run.session = session
		activeRunsByID[jobID] = run
		lock.unlock()

		if isResume, job.phase == .importing {
			session.restore(status: job.statusText, fractionCompleted: job.fractionCompleted, phase: .importing)
			resumeImport(job: job, session: session, core: core, hostViewController: hostViewController)
		} else {
			if isResume {
				session.restore(status: job.statusText, fractionCompleted: job.fractionCompleted, phase: job.phase)
			}
			session.start()
		}
	}

	@discardableResult
	private func publishRecord(for job: ZipOperationJob) -> ZipOperationRecord {
		if let existing = ZipOperationCenter.shared.operations.first(where: { $0.id == job.id }) {
			existing.update(statusText: job.statusText, fractionCompleted: job.fractionCompleted)
			existing.cancelHandler = { [weak self] in
				self?.cancel(jobID: job.id)
			}
			ZipOperationCenter.shared.update(existing, statusText: job.statusText, fractionCompleted: job.fractionCompleted)
			return existing
		}

		let record = ZipOperationRecord(
			id: job.id,
			kind: job.kind == .compress ? .compress : .decompress,
			documentName: job.documentName,
			parentLocationKey: job.parentLocationKey,
			parentItemLocalID: job.parentItemLocalID,
			statusText: job.statusText,
			fractionCompleted: job.fractionCompleted
		)
		record.cancelHandler = { [weak self] in
			self?.cancel(jobID: job.id)
		}
		ZipOperationCenter.shared.add(record)
		return record
	}

	private func handleSessionCompletion(error: Error?, result: ZipOperationResult?, session: ZipOperationSession, core: OCCore, hostViewController: UIViewController?) {
		guard let run = run(for: session), !run.isCancelling else { return }

		if let error {
			if (error as NSError).isOCError(withCode: .cancelled) {
				return
			}
			markFailed(run: run, error: error, hostViewController: hostViewController)
			return
		}

		guard let result else {
			markFailed(run: run, error: NSError(ocError: .internal), hostViewController: hostViewController)
			return
		}

		switch result.kind {
		case .compress(let archiveURL, let fileName, let parentItem):
			let durableURL = run.job.workingDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
			if archiveURL.standardizedFileURL != durableURL.standardizedFileURL {
				try? FileManager.default.removeItem(at: durableURL)
				do {
					try FileManager.default.copyItem(at: archiveURL, to: durableURL)
					try? FileManager.default.removeItem(at: archiveURL)
				} catch {
					try? FileManager.default.moveItem(at: archiveURL, to: durableURL)
				}
			}
			run.job.archiveFileName = fileName
			run.job.suggestedUploadName = fileName
			run.job.phase = .importing
			persist(run.job, core: core)
			session.beginImportPhase()
			startCompressImport(archiveURL: durableURL, fileName: fileName, parentItem: parentItem, session: session, core: core, hostViewController: hostViewController)

		case .decompress(let extractURL, let parentItem):
			let durableExtract = run.job.extractDirectoryURL
			if extractURL.standardizedFileURL != durableExtract.standardizedFileURL {
				try? FileManager.default.removeItem(at: durableExtract)
				do {
					try FileManager.default.moveItem(at: extractURL, to: durableExtract)
				} catch {
					try? FileManager.default.copyItem(at: extractURL, to: durableExtract)
					try? FileManager.default.removeItem(at: extractURL)
				}
			}
			run.job.phase = .importing
			persist(run.job, core: core)
			session.beginImportPhase()
			startDecompressImport(extractURL: durableExtract, parentItem: parentItem, session: session, core: core, hostViewController: hostViewController)
		}
	}

	private func resumeImport(job: ZipOperationJob, session: ZipOperationSession, core: OCCore, hostViewController: UIViewController?) {
		session.beginImportPhase()
		guard let parent = item(forLocalID: job.parentItemLocalID, core: core) else {
			session.start()
			return
		}

		switch job.kind {
		case .compress:
			if let placeholderID = job.uploadPlaceholderLocalID,
			   item(forLocalID: placeholderID, core: core) != nil {
				ZipDebugLogging.log("ZipOperationCoordinator.resumeImport: compress placeholder already exists \(placeholderID)")
				if let run = activeRunsByID[job.id] {
					completeSuccessfully(run: run)
				}
				return
			}
			guard let archiveURL = job.archiveURL,
			      FileManager.default.fileExists(atPath: archiveURL.path),
			      let fileName = job.suggestedUploadName ?? job.archiveFileName else {
				session.start()
				return
			}
			startCompressImport(archiveURL: archiveURL, fileName: fileName, parentItem: parent, session: session, core: core, hostViewController: hostViewController)

		case .decompress:
			let extractURL = job.extractDirectoryURL
			if FileManager.default.fileExists(atPath: extractURL.path) {
				startDecompressImport(extractURL: extractURL, parentItem: parent, session: session, core: core, hostViewController: hostViewController)
			} else if !job.uploadedFileLocalIDs.isEmpty || !job.createdFolderLocalIDs.isEmpty {
				if let run = activeRunsByID[job.id] {
					completeSuccessfully(run: run)
				}
			} else {
				session.start()
			}
		}
	}

	private func startCompressImport(archiveURL: URL, fileName: String, parentItem: OCItem, session: ZipOperationSession, core: OCCore, hostViewController: UIViewController?) {
		guard let run = run(for: session) else { return }

		let progress = archiveURL.upload(with: core, at: parentItem, alternativeName: fileName, importByCopy: true, placeholderHandler: { [weak self] item, error in
			guard let self, let run = self.run(for: session), !run.isCancelling else { return }

			if let error {
				if (error as NSError).isOCError(withCode: .cancelled) {
					return
				}
				self.markFailed(run: run, error: error, hostViewController: hostViewController)
				return
			}

			run.job.uploadPlaceholderLocalID = item?.localID as String?
			self.persist(run.job, core: core)
			// Job completes on placeholder creation; sync engine uploads in the background.
			self.completeSuccessfully(run: run)
		}, completionHandler: { _, error in
			// Server upload is out of zip progress — log only.
			if let error {
				ZipDebugLogging.log(error: error, context: "ZipOperationCoordinator.compressImport.server")
			} else {
				ZipDebugLogging.log("ZipOperationCoordinator.compressImport: server upload finished for \(Log.mask(fileName))")
			}
		})

		guard let progress else {
			markFailed(run: run, error: NSError(ocError: .internal), hostViewController: hostViewController)
			return
		}

		trackImport(progress, for: run, session: session)
	}

	private func startDecompressImport(extractURL: URL, parentItem: OCItem, session: ZipOperationSession, core: OCCore, hostViewController: UIViewController?) {
		guard let run = run(for: session) else { return }
		let skipPaths = Set(run.job.uploadedRelativePaths)

		ZipArchiveService.importExtractedContents(
			at: extractURL,
			to: parentItem,
			core: core,
			skipRelativePaths: skipPaths,
			publishProgress: { [weak self] importProgress in
				guard let self, let run = self.run(for: session) else { return }
				self.trackImport(importProgress, for: run, session: session)
			},
			onProgressCreated: { [weak self] progress in
				guard let self, let run = self.run(for: session) else { return }
				run.importProgresses.append(progress)
				session.registerImportProgress(progress)
			},
			onItemCreated: { [weak self] event in
				guard let self, let run = self.run(for: session) else { return }
				switch event.kind {
				case .folder:
					if !run.job.createdFolderLocalIDs.contains(event.localID) {
						run.job.createdFolderLocalIDs.append(event.localID)
					}
				case .file:
					if !run.job.uploadedFileLocalIDs.contains(event.localID) {
						run.job.uploadedFileLocalIDs.append(event.localID)
					}
				}
				if !run.job.uploadedRelativePaths.contains(event.relativePath) {
					run.job.uploadedRelativePaths.append(event.relativePath)
				}
				self.persist(run.job, core: core)
			},
			completion: { [weak self] error in
				guard let self, let run = self.run(for: session), !run.isCancelling else { return }

				if let error {
					if (error as NSError).isOCError(withCode: .cancelled) {
						return
					}
					self.markFailed(run: run, error: error, hostViewController: hostViewController)
					return
				}

				self.completeSuccessfully(run: run)
			}
		)
	}

	private func trackImport(_ progress: Progress, for run: ActiveRun, session: ZipOperationSession) {
		run.importProgresses.append(progress)
		session.registerImportProgress(progress)
		run.job.phase = .importing
		persist(run.job, core: run.core)

		let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self, weak session] progress, _ in
			guard let self, let session else { return }
			session.updateImportProgress(progress)
			self.sessionDidUpdate(session, status: HCL10n.ZipAction.Progress.importing, fraction: 0.9 + progress.fractionCompleted * 0.1, phase: .importing)
		}
		run.importObservations.append(observation)
	}

	private func completeSuccessfully(run: ActiveRun) {
		let job = run.job
		let core = run.core
		let hostViewController = run.hostViewController
		let recordKind: ZipOperationRecord.Kind = job.kind == .compress ? .compress : .decompress
		let parentLocationKey = job.parentLocationKey
		let revealLocalID = revealLocalID(for: job)
		let compressedItemCount = job.sourceItemLocalIDs.count

		tearDown(jobID: job.id, purgeWorkingDirectory: true)

		OnMainThread { [weak self, weak hostViewController] in
			ZipOperationToastPresenter.showSuccess(
				kind: recordKind,
				itemCount: compressedItemCount,
				on: hostViewController
			) {
				guard let self, let core, let revealLocalID,
				      let item = self.item(forLocalID: revealLocalID, core: core) else {
					return
				}
				ZipOperationToastPresenter.revealItem(
					item,
					parentLocationKey: parentLocationKey,
					from: hostViewController,
					clientContext: nil,
					core: core
				)
			}
		}
	}

	private func markFailed(run: ActiveRun, error: Error, hostViewController: UIViewController?) {
		let recordKind: ZipOperationRecord.Kind = run.job.kind == .compress ? .compress : .decompress
		let zipError = ZipArchiveError.classify(error, for: recordKind)
		run.job.phase = .failed
		run.job.lastErrorDescription = zipError.localizedMessage(for: recordKind)
		run.job.statusText = run.job.lastErrorDescription ?? HCL10n.ZipAction.Progress.preparing
		persist(run.job, core: run.core)
		// Drop from the activity queue immediately; Retry re-publishes via resume().
		ZipOperationCenter.shared.remove(id: run.job.id)
		run.backgroundTask?.end()
		run.backgroundTask = nil
		run.importObservations.removeAll()
		run.session = nil

		lock.lock()
		activeRunsByID.removeValue(forKey: run.job.id)
		lock.unlock()

		let jobID = run.job.id
		let preferredAnchor = hostViewController ?? run.hostViewController
		let canRetry = zipError.showsRetry

		OnMainThread { [weak self, weak preferredAnchor] in
			guard let self else { return }
			let anchor = ZipOperationToastPresenter.resolvePresentationAnchor(preferred: preferredAnchor)
			if zipError.presentsAlert {
				guard let presenter = (anchor ?? preferredAnchor)?.topMostViewController else {
					self.abandonFailedJob(jobID: jobID)
					return
				}
				let alert = ThemedAlertController(
					with: HCL10n.ZipAction.Alert.UnsupportedArchive.title,
					message: HCL10n.ZipAction.Alert.UnsupportedArchive.message,
					okLabel: HCL10n.Common.ok,
					preferredStyle: .alert,
					action: nil
				)
				presenter.present(alert, animated: true)
				self.abandonFailedJob(jobID: jobID)
				return
			}

			if canRetry {
				ZipOperationToastPresenter.showError(
					zipError,
					kind: recordKind,
					on: preferredAnchor,
					onRetry: { [weak self] in
						self?.retry(jobID: jobID)
					},
					onDismissWithoutRetry: { [weak self] in
						self?.abandonFailedJob(jobID: jobID)
					}
				)
			} else {
				self.abandonFailedJob(jobID: jobID)
				ZipOperationToastPresenter.showError(zipError, kind: recordKind, on: preferredAnchor)
			}
		}
	}

	/// Clears a failed job that will not be retried (toast dismissed / non-retryable alert).
	private func abandonFailedJob(jobID: String) {
		lock.lock()
		let isActive = activeRunsByID[jobID] != nil
		lock.unlock()
		guard !isActive else { return }

		for bookmark in OCBookmarkManager.shared.bookmarks {
			guard let job = bookmark.zipOperationStore.jobsByID[jobID], job.phase == .failed else { continue }
			job.removeWorkingDirectory()
			OCCoreManager.shared.requestCore(for: bookmark, setup: nil) { [weak self] core, _ in
				guard let self else { return }
				if let core {
					self.deleteUploadPlaceholderIfNeeded(job: job, core: core)
					self.deleteDecompressImportOrphans(job: job, core: core)
					OCCoreManager.shared.returnCore(for: bookmark, completionHandler: nil)
				}
				bookmark.removeZipJob(id: jobID)
				ZipOperationCenter.shared.remove(id: jobID)
			}
			return
		}
		ZipOperationCenter.shared.remove(id: jobID)
	}

	private func revealLocalID(for job: ZipOperationJob) -> String? {
		switch job.kind {
		case .compress:
			return job.uploadPlaceholderLocalID
		case .decompress:
			if job.createdFolderLocalIDs.count == 1 {
				return job.createdFolderLocalIDs.first
			}
			return job.uploadedFileLocalIDs.first ?? job.createdFolderLocalIDs.first
		}
	}

	private func deleteUploadPlaceholderIfNeeded(job: ZipOperationJob, core: OCCore) {
		guard let placeholderID = job.uploadPlaceholderLocalID,
		      let item = item(forLocalID: placeholderID, core: core) else {
			return
		}
		if let progresses = core.progressForItem(withLocalID: placeholderID, matching: .none) {
			progresses.forEach { $0.cancel() }
		}
		_ = core.delete(item, requireMatch: false, resultHandler: nil)
	}

	private func deleteDecompressImportOrphans(job: ZipOperationJob, core: OCCore) {
		let fileIDs = job.uploadedFileLocalIDs
		let folderIDs = job.createdFolderLocalIDs

		for localID in fileIDs {
			if let progresses = core.progressForItem(withLocalID: localID, matching: .none) {
				progresses.forEach { $0.cancel() }
			}
			guard let item = item(forLocalID: localID, core: core) else { continue }
			_ = core.delete(item, requireMatch: false, resultHandler: nil)
		}

		let folders: [(String, OCItem)] = folderIDs.compactMap { localID in
			guard let item = item(forLocalID: localID, core: core) else { return nil }
			return (localID, item)
		}
		.sorted { lhs, rhs in
			(lhs.1.path ?? "").split(separator: "/").count > (rhs.1.path ?? "").split(separator: "/").count
		}

		for (localID, item) in folders {
			if let progresses = core.progressForItem(withLocalID: localID, matching: .none) {
				progresses.forEach { $0.cancel() }
			}
			_ = core.delete(item, requireMatch: false, resultHandler: nil)
		}
	}

	private func tearDown(jobID: String, purgeWorkingDirectory: Bool) {
		lock.lock()
		let run = activeRunsByID.removeValue(forKey: jobID)
		lock.unlock()

		run?.importObservations.removeAll()
		run?.backgroundTask?.end()

		if let job = run?.job {
			if purgeWorkingDirectory {
				job.removeWorkingDirectory()
			}
			if let bookmark = OCBookmarkManager.shared.bookmark(forUUIDString: job.bookmarkUUID.uuidString) {
				bookmark.removeZipJob(id: jobID)
			} else {
				run?.core?.bookmark.removeZipJob(id: jobID)
			}
		}

		ZipOperationCenter.shared.remove(id: jobID)
	}

	private func persist(_ job: ZipOperationJob, core: OCCore?) {
		(core?.bookmark ?? OCBookmarkManager.shared.bookmark(forUUIDString: job.bookmarkUUID.uuidString))?.saveZipJob(job)
	}

	private func run(for session: ZipOperationSession) -> ActiveRun? {
		lock.lock()
		defer { lock.unlock() }
		return activeRunsByID.values.first { $0.session === session }
	}

	private func location(for item: OCItem, bookmarkUUID: UUID) -> OCLocation? {
		guard let location = item.location else { return nil }
		if location.bookmarkUUID == nil {
			location.bookmarkUUID = bookmarkUUID
		}
		return location
	}

	private func operation(for job: ZipOperationJob, core: OCCore) -> ZipOperationSession.Operation? {
		switch job.kind {
		case .compress:
			let items = job.sourceItemLocalIDs.compactMap { item(forLocalID: $0, core: core) }
			let parent = item(forLocalID: job.parentItemLocalID, core: core) ?? items.first?.parentItem(from: core)
			guard let parent, !items.isEmpty else { return nil }
			return .compress(items: items, parentItem: parent)
		case .decompress:
			guard let zipID = job.zipItemLocalID,
			      let zipItem = item(forLocalID: zipID, core: core),
			      let parent = item(forLocalID: job.parentItemLocalID, core: core) ?? zipItem.parentItem(from: core) else {
				return nil
			}
			return .decompress(zipItem: zipItem, parentItem: parent)
		}
	}

	private func item(forLocalID localID: String?, core: OCCore) -> OCItem? {
		guard let localID, let database = core.vault.database else { return nil }
		var found: OCItem?
		let semaphore = DispatchSemaphore(value: 0)
		database.retrieveCacheItem(forLocalID: localID, completionHandler: { _, _, _, item in
			found = item
			semaphore.signal()
		})
		_ = semaphore.wait(timeout: .now() + 5)
		return found
	}
}
