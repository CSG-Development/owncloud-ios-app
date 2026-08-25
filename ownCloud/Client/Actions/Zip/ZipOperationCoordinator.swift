import UIKit
import ownCloudSDK
import ownCloudAppShared

/// Owns zip job persistence, background execution, cancel cleanup, and resume across launches.
/// Job completes when vault placeholders are created; server upload is handled by normal sync.
/// At most one compress/decompress run executes at a time; additional jobs wait in FIFO order.
final class ZipOperationCoordinator {
	static let shared = ZipOperationCoordinator()

	private static let maxConcurrentActiveRuns = 1

	private final class ActiveRun {
		let job: ZipOperationJob
		let record: ZipOperationRecord
		var session: ZipOperationSession?
		private var importProgresses: [Progress] = []
		private var importObservations: [NSKeyValueObservation] = []
		private let stateQueue = DispatchQueue(label: "com.owncloud.zip-coordinator.active-run-state")
		var backgroundTask: OCBackgroundTask?
		weak var core: OCCore?
		weak var hostViewController: UIViewController?
		var isCancelling = false
		var lastPersistedAt: Date = .distantPast
		var lastPersistedPhase: ZipOperationPhase?
		var claims: ZipOperationClaims?

		init(job: ZipOperationJob, record: ZipOperationRecord) {
			self.job = job
			self.record = record
			self.lastPersistedPhase = job.phase
		}

		func appendImportProgress(_ progress: Progress) {
			stateQueue.sync {
				importProgresses.append(progress)
			}
		}

		func snapshotImportProgresses() -> [Progress] {
			stateQueue.sync { importProgresses }
		}

		func appendImportObservation(_ observation: NSKeyValueObservation) {
			stateQueue.sync {
				importObservations.append(observation)
			}
		}

		func clearImportObservations() {
			stateQueue.sync {
				importObservations.removeAll()
			}
		}
	}

	private struct PendingStart {
		let job: ZipOperationJob
		let core: OCCore
		weak var hostViewController: UIViewController?
		let operation: ZipOperationSession.Operation
		let isResume: Bool
	}

	private let stateQueue = DispatchQueue(label: "com.owncloud.zip-coordinator.state")
	private var activeRunsByID: [String: ActiveRun] = [:]
	private var pendingStarts: [PendingStart] = []

	/// Serial queue that owns all OCKeyValueStore writes for zip jobs.
	/// OCKeyValueStore.updateObject(forKey:usingModifier:) blocks its caller via
	/// OCWaitForCompletion until the NSFileCoordinator write on _coordinationQueue
	/// finishes. Dispatching those writes here keeps them off the main thread entirely.
	private let persistenceQueue = DispatchQueue(label: "com.owncloud.zip-coordinator.persist", qos: .background)

	private init() {}

	// MARK: - Start

	func startCompress(items: [OCItem], parentItem: OCItem, core: OCCore, hostViewController: UIViewController?) {
		let bookmarkUUID = core.bookmark.uuid
		let parentLocation = location(for: parentItem, bookmarkUUID: bookmarkUUID)
		let job = ZipOperationJob(
			kind: .compress,
			bookmarkUUID: bookmarkUUID,
			documentName: ZipArchiveService.suggestedArchiveName(for: items),
			parentLocationKey: ZipOperationRecord.locationKey(for: parentLocation) ?? "",
			parentItemLocalID: parentItem.localID as String?,
			sourceItemLocalIDs: items.compactMap { $0.localID as String? }
		)

		begin(job: job, core: core, hostViewController: hostViewController, operation: .compress(items: items, parentItem: parentItem))
	}

	func startDecompress(zipItem: OCItem, parentItem: OCItem, core: OCCore, hostViewController: UIViewController?) {
		let bookmarkUUID = core.bookmark.uuid
		let parentLocation = location(for: parentItem, bookmarkUUID: bookmarkUUID)
		let job = ZipOperationJob(
			kind: .decompress,
			bookmarkUUID: bookmarkUUID,
			documentName: zipItem.name ?? HCL10n.ZipAction.defaultArchiveName,
			parentLocationKey: ZipOperationRecord.locationKey(for: parentLocation) ?? "",
			parentItemLocalID: parentItem.localID as String?,
			sourceItemLocalIDs: [],
			zipItemLocalID: zipItem.localID as String?
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
				DispatchQueue.global(qos: .background).async {
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
					let jobID = job.id
					persistenceQueue.async { bookmark.removeZipJob(id: jobID) }
					ZipOperationCenter.shared.remove(id: job.id)
					continue
				}
				publishRecord(for: job)
			}
		}
	}

	private func resume(job: ZipOperationJob, core: OCCore, preresolvedOperation: ZipOperationSession.Operation? = nil) {
		let (alreadyActive, alreadyPending) = stateQueue.sync {
			(activeRunsByID[job.id] != nil, pendingStarts.contains { $0.job.id == job.id })
		}
		guard !alreadyActive, !alreadyPending, job.phase != .completed else { return }

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

		ZipDebugLogging.log("ZipOperationCoordinator.resume: id=\(job.id) phase=\(job.phase.rawValue)")

		// All callers pre-resolve the operation on a background queue to avoid blocking
		// the main thread. If pre-resolution returned nil the items are gone — fail fast.
		guard let operation = preresolvedOperation else {
			job.phase = .failed
			job.lastErrorDescription = "Missing items"
			job.statusText = job.lastErrorDescription ?? HCL10n.ZipAction.Progress.preparing
			let bookmark = core.bookmark
			persistenceQueue.async { bookmark.saveZipJob(job) }
			ZipOperationCenter.shared.remove(id: job.id)
			ZipDebugLogging.log("ZipOperationCoordinator.resume: missing items for \(job.id)")
			return
		}

		begin(job: job, core: core, hostViewController: nil, operation: operation, isResume: true)
	}

	// MARK: - Cancel

	func cancel(jobID: String) {
		if let pending = stateQueue.sync(execute: { () -> PendingStart? in
			guard let pendingIndex = pendingStarts.firstIndex(where: { $0.job.id == jobID }) else { return nil }
			return pendingStarts.remove(at: pendingIndex)
		}) {
			ZipDebugLogging.log("ZipOperationCoordinator.cancel: queued id=\(jobID)")
			pending.job.removeWorkingDirectory()
			let bookmark = pending.core.bookmark
			persistenceQueue.async { bookmark.removeZipJob(id: jobID) }
			ZipOperationCenter.shared.remove(id: jobID)
			return
		}

		guard let run = stateQueue.sync(execute: { activeRunsByID[jobID] }) else {
			cancelPersistedOnly(jobID: jobID)
			return
		}
		stateQueue.sync {
			run.isCancelling = true
		}
		let importProgresses = run.snapshotImportProgresses()
		let session = run.session
		let core = run.core
		let job = run.job

		ZipDebugLogging.log("ZipOperationCoordinator.cancel: id=\(jobID)")

		for progress in importProgresses {
			progress.cancel()
		}
		session?.cancelFromCoordinator()

		if let core {
			// Both helpers call item(forLocalID:core:) which blocks on a semaphore —
			// always dispatch off the main thread.
			let jobCapture = job
			let coreCapture = core
			DispatchQueue.global(qos: .background).async { [weak self] in
				self?.deleteUploadPlaceholderIfNeeded(job: jobCapture, core: coreCapture)
				self?.deleteDecompressImportOrphans(job: jobCapture, core: coreCapture)
			}
		}

		tearDown(jobID: jobID, purgeWorkingDirectory: true)
	}

	private func cancelPersistedOnly(jobID: String) {
		stateQueue.sync {
			pendingStarts.removeAll { $0.job.id == jobID }
		}

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
				// Pre-resolve OCItems off the main thread (blocking DB semaphore),
				// matching the pattern used in resumePendingJobs().
				DispatchQueue.global(qos: .background).async {
					let operation = self.operation(for: job, core: core)
					OnMainThread {
						self.resume(job: job, core: core, preresolvedOperation: operation)
					}
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

	func sessionClaimItems(_ session: ZipOperationSession, items: [OCItem], completion: (() -> Void)? = nil) {
		guard let run = run(for: session), let claims = run.claims else {
			completion?()
			return
		}
		claims.claim(items, completion: completion)
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
		_ = publishRecord(for: job)

		let shouldQueue = stateQueue.sync { () -> Bool in
			if activeRunsByID[job.id] != nil {
				return false
			}
			if pendingStarts.contains(where: { $0.job.id == job.id }) {
				return false
			}
			if activeRunsByID.count >= Self.maxConcurrentActiveRuns {
				pendingStarts.append(PendingStart(
					job: job,
					core: core,
					hostViewController: hostViewController,
					operation: operation,
					isResume: isResume
				))
				return true
			}
			return false
		}
		if shouldQueue {
			markJobWaiting(job, core: core)
			ZipDebugLogging.log("ZipOperationCoordinator.begin: queued id=\(job.id)")
			return
		}

		let isAlreadyPresent = stateQueue.sync {
			activeRunsByID[job.id] != nil || pendingStarts.contains(where: { $0.job.id == job.id })
		}
		if isAlreadyPresent {
			return
		}

		startActiveRun(job: job, core: core, hostViewController: hostViewController, operation: operation, isResume: isResume)
	}

	private func markJobWaiting(_ job: ZipOperationJob, core: OCCore) {
		job.statusText = HCL10n.ZipAction.Progress.waiting
		persist(job, core: core)
		if let existing = ZipOperationCenter.shared.operations.first(where: { $0.id == job.id }) {
			ZipOperationCenter.shared.update(existing, statusText: job.statusText, fractionCompleted: job.fractionCompleted)
		} else {
			_ = publishRecord(for: job)
		}
	}

	private func startNextQueuedIfNeeded() {
		let nextAndRemaining = stateQueue.sync { () -> (PendingStart?, Int) in
			guard activeRunsByID.count < Self.maxConcurrentActiveRuns, !pendingStarts.isEmpty else {
				return (nil, pendingStarts.count)
			}
			let next = pendingStarts.removeFirst()
			return (next, pendingStarts.count)
		}
		guard let next = nextAndRemaining.0 else { return }
		let remaining = nextAndRemaining.1

		ZipDebugLogging.log("ZipOperationCoordinator.startNextQueued: id=\(next.job.id) remainingPending=\(remaining)")
		startActiveRun(
			job: next.job,
			core: next.core,
			hostViewController: next.hostViewController,
			operation: next.operation,
			isResume: next.isResume
		)
	}

	private func startActiveRun(
		job: ZipOperationJob,
		core: OCCore,
		hostViewController: UIViewController?,
		operation: ZipOperationSession.Operation,
		isResume: Bool
	) {
		if job.statusText == HCL10n.ZipAction.Progress.waiting {
			switch job.phase {
			case .downloading:
				job.statusText = HCL10n.ZipAction.Progress.downloading
			case .archiving:
				job.statusText = job.kind == .compress
					? HCL10n.ZipAction.Progress.compressing
					: HCL10n.ZipAction.Progress.decompressing
			case .importing:
				job.statusText = HCL10n.ZipAction.Progress.importing
			case .preparing, .failed, .completed:
				job.statusText = HCL10n.ZipAction.Progress.preparing
			}
			persist(job, core: core)
			_ = publishRecord(for: job)
		}

		let record = publishRecord(for: job)

		let run = ActiveRun(job: job, record: record)
		run.core = core
		run.hostViewController = hostViewController
		run.claims = ZipOperationClaims(jobID: job.id, core: core)
		run.claims?.claim(Self.initialClaimItems(for: operation), completion: nil)
		run.backgroundTask = OCBackgroundTask(name: "com.owncloud.zip-operation-\(job.id)", expirationHandler: { [weak self] bgTask in
			ZipDebugLogging.log("ZipOperationCoordinator: background task expired for \(job.id)")
			var sessionToCancel: ZipOperationSession?
			var claimsToRelease: ZipOperationClaims?
			var shouldStartNext = false
			self?.stateQueue.sync {
				if let active = self?.activeRunsByID[job.id] {
					active.job.lastErrorDescription = "Interrupted"
					if active.job.phase != .importing {
						active.job.phase = .failed
						if let core = active.core {
							self?.persist(active.job, core: core)
						}
						ZipOperationCenter.shared.remove(id: active.job.id)
						sessionToCancel = active.session
						claimsToRelease = active.claims
						active.claims = nil
						active.session = nil
						self?.activeRunsByID.removeValue(forKey: job.id)
						shouldStartNext = true
					} else if let core = active.core {
						self?.persist(active.job, core: core)
					}
				}
			}
			claimsToRelease?.releaseAll()
			sessionToCancel?.cancelFromCoordinator()
			bgTask.end()
			if shouldStartNext {
				self?.startNextQueuedIfNeeded()
			}
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
			let session = self.stateQueue.sync { self.activeRunsByID[jobID]?.session }
			guard let session else { return }
			self.handleSessionCompletion(error: error, result: result, session: session, core: core, hostViewController: hostViewController)
		}

		let shouldRequeue = stateQueue.sync { () -> Bool in
			// Another start may have raced in; if the slot is taken, re-queue.
			if activeRunsByID.count >= Self.maxConcurrentActiveRuns, activeRunsByID[jobID] == nil {
				pendingStarts.insert(PendingStart(
					job: job,
					core: core,
					hostViewController: hostViewController,
					operation: operation,
					isResume: isResume
				), at: 0)
				return true
			}
			run.session = session
			activeRunsByID[jobID] = run
			return false
		}
		if shouldRequeue {
			run.backgroundTask?.end()
			markJobWaiting(job, core: core)
			return
		}

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
			let durableProfile = ZipDebugLogging.ProfileScope(
				"decompress.durableMove",
				extra: "job=\(run.job.id)"
			)
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
			durableProfile.end()
			run.job.phase = .importing
			persist(run.job, core: core)
			session.beginImportPhase()
			startDecompressImport(extractURL: durableExtract, parentItem: parentItem, session: session, core: core, hostViewController: hostViewController)
		}
	}

	private func resumeImport(job: ZipOperationJob, session: ZipOperationSession, core: OCCore, hostViewController: UIViewController?) {
		session.beginImportPhase()
		// Item lookups use a blocking DB semaphore — run them off the main thread.
		DispatchQueue.global(qos: .background).async { [weak self] in
			guard let self else { return }
			guard let parent = self.item(forLocalID: job.parentItemLocalID, core: core) else {
				OnMainThread { session.start() }
				return
			}

			switch job.kind {
			case .compress:
				let placeholder: OCItem? = job.uploadPlaceholderLocalID != nil
					? self.item(forLocalID: job.uploadPlaceholderLocalID, core: core)
					: nil
				OnMainThread {
					if let placeholderID = job.uploadPlaceholderLocalID, placeholder != nil {
						ZipDebugLogging.log("ZipOperationCoordinator.resumeImport: compress placeholder already exists \(placeholderID)")
						let run = self.stateQueue.sync { self.activeRunsByID[job.id] }
						if let run { self.completeSuccessfully(run: run) }
						return
					}
					guard let archiveURL = job.archiveURL,
					      FileManager.default.fileExists(atPath: archiveURL.path),
					      let fileName = job.suggestedUploadName ?? job.archiveFileName else {
						session.start()
						return
					}
					self.startCompressImport(archiveURL: archiveURL, fileName: fileName, parentItem: parent, session: session, core: core, hostViewController: hostViewController)
				}

			case .decompress:
				OnMainThread {
					let extractURL = job.extractDirectoryURL
					if FileManager.default.fileExists(atPath: extractURL.path) {
						self.startDecompressImport(extractURL: extractURL, parentItem: parent, session: session, core: core, hostViewController: hostViewController)
					} else if !job.uploadedFileLocalIDs.isEmpty || !job.createdFolderLocalIDs.isEmpty {
						let run = self.stateQueue.sync { self.activeRunsByID[job.id] }
						if let run { self.completeSuccessfully(run: run) }
					} else {
						session.start()
					}
				}
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
			if let item {
				run.claims?.claim([item])
			}
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
		let importProfile = ZipDebugLogging.ProfileScope(
			"decompress.import",
			extra: "job=\(run.job.id) skip=\(skipPaths.count)"
		)

		ZipArchiveService.importExtractedContents(
			at: extractURL,
			to: parentItem,
			core: core,
			skipRelativePaths: skipPaths,
			publishProgress: { [weak self] importProgress in
				OnMainThread(inline: true) {
					guard let self, let run = self.run(for: session) else { return }
					self.trackImport(importProgress, for: run, session: session)
				}
			},
			onProgressCreated: { [weak self] progress in
				OnMainThread(inline: true) {
					guard let self, let run = self.run(for: session) else { return }
					run.appendImportProgress(progress)
					session.registerImportProgress(progress)
				}
			},
			onItemCreated: { [weak self] event in
				OnMainThread(inline: true) {
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
				// Do not claim each imported placeholder — that mutates the item DB and
				// refreshes ItemList queries once per file (very expensive on large extracts).
				// Source zip + parent are already claimed for the operation lifetime.
				// Throttle persistence; in-memory job state is used for cancel cleanup.
				self.persistProgressIfNeeded(run: run, force: false)
				}
			},
			completion: { [weak self] error in
				OnMainThread(inline: true) {
					guard let self, let run = self.run(for: session), !run.isCancelling else {
						importProfile.end(extra: "cancelledOrGone")
						return
					}

				if let error {
					if (error as NSError).isOCError(withCode: .cancelled) {
						importProfile.end(extra: "cancelled")
						return
					}
					importProfile.end(extra: "failed")
					self.persist(run.job, core: core)
					self.markFailed(run: run, error: error, hostViewController: hostViewController)
					return
				}

				importProfile.end(
					extra: "ok files=\(run.job.uploadedFileLocalIDs.count) folders=\(run.job.createdFolderLocalIDs.count)"
				)
				self.completeSuccessfully(run: run)
				}
			}
		)
	}

	private func trackImport(_ progress: Progress, for run: ActiveRun, session: ZipOperationSession) {
		run.appendImportProgress(progress)
		session.registerImportProgress(progress)
		run.job.phase = .importing
		persist(run.job, core: run.core)

		let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self, weak session] progress, _ in
			guard let self, let session else { return }
			session.updateImportProgress(progress)
			// sessionDidUpdate accesses job properties and updates UI — must run on main thread.
			OnMainThread(inline: true) {
				self.sessionDidUpdate(session, status: HCL10n.ZipAction.Progress.importing, fraction: 0.9 + progress.fractionCompleted * 0.1, phase: .importing)
			}
		}
		run.appendImportObservation(observation)
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
				// item(forLocalID:core:) blocks — resolve on background then reveal on main.
				guard let self, let core, let revealLocalID else { return }
				DispatchQueue.global(qos: .background).async {
					guard let item = self.item(forLocalID: revealLocalID, core: core) else { return }
					OnMainThread {
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
		}
	}

	private func markFailed(run: ActiveRun, error: Error, hostViewController: UIViewController?) {
		let recordKind: ZipOperationRecord.Kind = run.job.kind == .compress ? .compress : .decompress
		let zipError = ZipArchiveError.classify(error, for: recordKind)
		run.job.phase = .failed
		run.job.lastErrorDescription = zipError.localizedMessage(for: recordKind)
		run.job.statusText = run.job.lastErrorDescription ?? HCL10n.ZipAction.Progress.preparing
		persist(run.job, core: run.core)
		run.claims?.releaseAll()
		run.claims = nil
		// Drop from the activity queue immediately; Retry re-publishes via resume().
		ZipOperationCenter.shared.remove(id: run.job.id)
		run.backgroundTask?.end()
		run.backgroundTask = nil
		run.clearImportObservations()
		run.session = nil

		_ = stateQueue.sync {
			activeRunsByID.removeValue(forKey: run.job.id)
		}

		startNextQueuedIfNeeded()

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
		let isActive = stateQueue.sync { activeRunsByID[jobID] != nil }
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
			// Multi-file / nested extracts create a container folder first (depth order).
			// Reveal that folder so View opens the extract, not a single inner file.
			return job.createdFolderLocalIDs.first ?? job.uploadedFileLocalIDs.first
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
		let run = stateQueue.sync { activeRunsByID.removeValue(forKey: jobID) }

		run?.claims?.releaseAll()
		run?.claims = nil
		run?.clearImportObservations()
		run?.backgroundTask?.end()

		if let job = run?.job {
			if purgeWorkingDirectory {
				// Remove temp files on the calling thread (fast filesystem op) before
				// the async store update so they don't linger if the queue is busy.
				job.removeWorkingDirectory()
			}
			let bookmark = OCBookmarkManager.shared.bookmark(forUUIDString: job.bookmarkUUID.uuidString)
				?? run?.core?.bookmark
			// Dispatch the blocking OCKeyValueStore write off the main thread.
			// persistenceQueue is serial so any in-flight persist for this job
			// will complete before the remove runs.
			persistenceQueue.async { bookmark?.removeZipJob(id: jobID) }
		}

		ZipOperationCenter.shared.remove(id: jobID)

		if run != nil {
			startNextQueuedIfNeeded()
		}
	}

	private func persist(_ job: ZipOperationJob, core: OCCore?) {
		// OCKeyValueStore.updateObject(forKey:usingModifier:) blocks its caller with
		// OCWaitForCompletion until the NSFileCoordinator disk write finishes (10–100 ms).
		// With N concurrent zip operations producing N progress ticks per second, calling
		// this on the main thread causes compounding stalls that freeze the UI entirely.
		// All job mutations happen on the main thread, so the background encode always
		// sees the latest-or-more-recent state — ideal for crash-recovery durability.
		guard let bookmark = core?.bookmark
			?? OCBookmarkManager.shared.bookmark(forUUIDString: job.bookmarkUUID.uuidString)
		else { return }
		persistenceQueue.async { bookmark.saveZipJob(job) }
	}

	private func run(for session: ZipOperationSession) -> ActiveRun? {
		stateQueue.sync {
			activeRunsByID.values.first { $0.session === session }
		}
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

	/// Blocking version — **must never be called from the main thread**.
	/// Use `item(forLocalID:core:completion:)` when on the main thread.
	private func item(forLocalID localID: String?, core: OCCore) -> OCItem? {
		assert(!Thread.isMainThread, "item(forLocalID:core:) blocks on a semaphore — do not call from the main thread")
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

	/// Non-blocking async item lookup. `completion` is called on an arbitrary queue.
	private func item(forLocalID localID: String?, core: OCCore, completion: @escaping (OCItem?) -> Void) {
		guard let localID, let database = core.vault.database else {
			completion(nil)
			return
		}
		database.retrieveCacheItem(forLocalID: localID, completionHandler: { _, _, _, item in
			completion(item)
		})
	}

	private static func initialClaimItems(for operation: ZipOperationSession.Operation) -> [OCItem] {
		switch operation {
		case .compress(let items, let parentItem):
			return items + [parentItem]
		case .decompress(let zipItem, let parentItem):
			return [zipItem, parentItem]
		}
	}
}

/// Holds read claims on every file/folder touched by a zip job until the run finishes.
/// Uses an explicit identifier per job so claims can be removed reliably without retaining claim objects.
final class ZipOperationClaims {
	private let explicitIdentifier: String
	private weak var core: OCCore?
	private let stateQueue = DispatchQueue(label: "com.owncloud.zip-coordinator.claims-state")
	private var claimedItemsByLocalID: [String: OCItem] = [:]
	private var released = false

	init(jobID: String, core: OCCore) {
		self.explicitIdentifier = "com.owncloud.zip-operation.\(jobID)"
		self.core = core
	}

	func claim(_ items: [OCItem], completion: (() -> Void)? = nil) {
		guard let core = core else {
			completion?()
			return
		}

		var toClaim: [OCItem] = []
		let shouldContinue = stateQueue.sync { () -> Bool in
			guard !released else { return false }
			for item in items {
				guard let localID = item.localID as String? else { continue }
				if claimedItemsByLocalID[localID] == nil {
					claimedItemsByLocalID[localID] = item
					toClaim.append(item)
				}
			}
			return true
		}
		guard shouldContinue else {
			completion?()
			return
		}

		guard !toClaim.isEmpty else {
			completion?()
			return
		}
		ZipDebugLogging.log("ZipOperationClaims.claim: adding \(toClaim.count) claim(s) id=\(explicitIdentifier)")

		let explicitIdentifier = self.explicitIdentifier
		DispatchQueue.global(qos: .utility).async { [weak self] in
			defer { completion?() }
			guard let self else { return }
			for item in toClaim {
				let shouldSkip = self.stateQueue.sync { self.released }
				if shouldSkip { return }

				let claim = OCClaim(
					forLifetimeOf: core,
					explicitIdentifier: explicitIdentifier,
					with: .read
				)
				core.add(claim, on: item, refreshItem: false, completionHandler: nil)
			}
		}
	}

	func releaseAll() {
		let releaseContext = stateQueue.sync { () -> (Bool, [OCItem], OCCore?, String) in
			guard !released else { return (false, [], nil, self.explicitIdentifier) }
			released = true
			let items = Array(claimedItemsByLocalID.values)
			claimedItemsByLocalID.removeAll()
			return (true, items, self.core, self.explicitIdentifier)
		}
		guard releaseContext.0 else {
			return
		}
		let items = releaseContext.1
		let releaseCore = releaseContext.2
		let releaseExplicitIdentifier = releaseContext.3

		guard let releaseCore, !items.isEmpty else { return }
		ZipDebugLogging.log("ZipOperationClaims.releaseAll: removing \(items.count) claim(s) id=\(releaseExplicitIdentifier)")

		DispatchQueue.global(qos: .utility).async {
			for item in items {
				releaseCore.removeClaims(withExplicitIdentifier: releaseExplicitIdentifier, on: item, refreshItem: false, completionHandler: nil)
			}
		}
	}
}
