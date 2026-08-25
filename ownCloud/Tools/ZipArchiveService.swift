//
//  ZipArchiveService.swift
//  ownCloud
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

import Foundation
import ZIPFoundation
import ownCloudSDK
import ownCloudAppShared

struct ZipArchiveEntry {
	let item: OCItem
	let archiveRelativePath: String
}

struct ZipLocalEntry {
	let archiveRelativePath: String
	let localURL: URL
}

struct ZipArchivePlan {
	let fileEntries: [ZipArchiveEntry]
	let emptyFolderPaths: [String]
	/// Folders visited while expanding the selection (including selected roots). Used for operation claims.
	let folderItems: [OCItem]

	/// All files and folders touched by this plan (for claims / diagnostics).
	var affectedItems: [OCItem] {
		var seen = Set<String>()
		var items: [OCItem] = []
		for item in folderItems + fileEntries.map(\.item) {
			guard let localID = item.localID as String?, seen.insert(localID).inserted else { continue }
			items.append(item)
		}
		return items
	}
}

enum ZipArchiveService {
	static func suggestedArchiveName(for items: [OCItem]) -> String {
		guard items.count == 1, let item = items.first, let name = item.name else {
			return dateBasedArchiveName()
		}

		if item.type == .collection {
			return "\(name).zip"
		}

		let baseName = (name as NSString).deletingPathExtension
		if baseName.isEmpty {
			return "\(name).zip"
		}

		return "\(baseName).zip"
	}

	private static func dateBasedArchiveName() -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"
		return "Archive_\(formatter.string(from: Date())).zip"
	}

	static func isZipArchive(_ item: OCItem) -> Bool {
		guard item.type == .file else { return false }

		if item.name?.lowercased().hasSuffix(".zip") == true {
			return true
		}

		if let mimeType = item.mimeType?.lowercased() {
			return mimeType == "application/zip" || mimeType == "application/x-zip-compressed"
		}

		return false
	}

	static func collectArchivePlan(for items: [OCItem], core: OCCore, completion: @escaping (Result<ZipArchivePlan, Error>) -> Void) {
		ZipDebugLogging.log(items: items, context: "collectArchivePlan.items")
		guard items.count > 0 else {
			ZipDebugLogging.log("collectArchivePlan: no items selected")
			completion(.failure(NSError(ocError: .insufficientParameters)))
			return
		}

		// Enumerate folder contents; files are materialized into the job downloads
		// directory (local copy or connection.downloadItem). makeAvailableOffline /
		// vault downloadItem are intentionally not used — claims hold locals for the
		// operation lifetime instead.
		collectArchivePlanEntries(for: items, core: core, completion: completion)
	}

	private static func collectArchivePlanEntries(for items: [OCItem], core: OCCore, completion: @escaping (Result<ZipArchivePlan, Error>) -> Void) {
		var fileEntries: [ZipArchiveEntry] = []
		var emptyFolderPaths: [String] = []
		var folderItems: [OCItem] = []
		let group = DispatchGroup()
		var firstError: Error?

		for item in items {
			if item.type == .file {
				guard let name = item.name else {
					ZipDebugLogging.log("collectArchivePlanEntries: skipping file item without name path=\(Log.mask(item.path ?? "nil"))")
					continue
				}
				let resolvedItem = resolvedItem(item, core: core)
				fileEntries.append(ZipArchiveEntry(item: resolvedItem, archiveRelativePath: name))
				ZipDebugLogging.log("collectArchivePlanEntries: added file \(Log.mask(name))")
				continue
			}

			guard item.type == .collection else {
				ZipDebugLogging.log("collectArchivePlanEntries: skipping unsupported type=\(item.type.rawValue) name=\(Log.mask(item.name ?? "nil"))")
				continue
			}

			ZipDebugLogging.log(item: item, context: "collectArchivePlanEntries.collectFolderContents")
			group.enter()
			collectFolderContents(folderItem: item, rootItem: item, core: core) { result in
				switch result {
				case .failure(let error):
					ZipDebugLogging.log(error: error, context: "collectArchivePlanEntries.collectFolderContents(\(Log.mask(item.name ?? "nil")))")
					if firstError == nil {
						firstError = error
					}
				case .success(let contents):
					ZipDebugLogging.log("collectArchivePlanEntries: folder \(Log.mask(item.name ?? "nil")) contributed \(contents.fileEntries.count) file(s), \(contents.emptyFolderPaths.count) empty folder path(s), \(contents.folderItems.count) folder(s)")
					fileEntries.append(contentsOf: contents.fileEntries)
					emptyFolderPaths.append(contentsOf: contents.emptyFolderPaths)
					folderItems.append(contentsOf: contents.folderItems)
				}
				group.leave()
			}
		}

		group.notify(queue: .main) {
			if let error = firstError {
				ZipDebugLogging.log(error: error, context: "collectArchivePlanEntries.completed")
				completion(.failure(error))
				return
			}

			if fileEntries.isEmpty && emptyFolderPaths.isEmpty {
				ZipDebugLogging.log("collectArchivePlanEntries: plan is empty — nothing to compress")
				completion(.failure(NSError(ocError: .insufficientParameters)))
				return
			}

			let downloadableFileEntries = fileEntries.filter { $0.item.type == .file }
			if downloadableFileEntries.count < fileEntries.count {
				ZipDebugLogging.log("collectArchivePlanEntries: filtered \(fileEntries.count - downloadableFileEntries.count) non-file entr\(fileEntries.count - downloadableFileEntries.count == 1 ? "y" : "ies") from plan")
			}

			let plan = ZipArchivePlan(
				fileEntries: downloadableFileEntries,
				emptyFolderPaths: emptyFolderPaths,
				folderItems: deduplicatedItems(folderItems)
			)
			ZipDebugLogging.log(plan: plan, context: "collectArchivePlanEntries")
			completion(.success(plan))
		}
	}

	/// Cancels an in-flight materialize pass so it cannot restart downloads after Cancel.
	final class ZipDownloadCancellationToken {
		private let lock = NSLock()
		private var _isCancelled = false
		private var downloadProgresses: [Progress] = []
		private var onCancel: (() -> Void)?

		var isCancelled: Bool {
			lock.lock()
			defer { lock.unlock() }
			return _isCancelled
		}

		func track(_ progress: Progress) {
			lock.lock()
			downloadProgresses.append(progress)
			let shouldCancel = _isCancelled
			lock.unlock()
			if shouldCancel {
				progress.cancel()
			}
		}

		func setCancelHandler(_ handler: @escaping () -> Void) {
			lock.lock()
			onCancel = handler
			lock.unlock()
		}

		func cancel() {
			lock.lock()
			guard !_isCancelled else {
				lock.unlock()
				return
			}
			_isCancelled = true
			let progresses = downloadProgresses
			let handler = onCancel
			onCancel = nil
			lock.unlock()

			for progress in progresses {
				progress.cancel()
			}
			handler?()
		}
	}

	/// Cap on simultaneous `connection.downloadItem` calls while materializing a plan.
	/// Local copies / resume hits do not consume a slot. Tune for network vs. server load.
	private static let maxConcurrentDownloads: Int = 5

	/// Cap on simultaneous PROPFIND depth=1 calls while expanding sibling folders.
	private static let maxConcurrentFolderEnumerations = 5

	/// Cap on simultaneous `importFileNamed` calls while importing an extract.
	private static let maxConcurrentImports = 5

	/// Copies offline locals or downloads via `connection.downloadItem(_:to:)` into `downloadsDirectory`.
	/// Never writes into the vault. Callers hold `OCClaim`s on affected items for the operation lifetime.
	/// File copies and download enqueue run on a utility queue so callers on the main thread stay responsive.
	@discardableResult
	static func materializeArchiveEntries(
		_ plan: ZipArchivePlan,
		core: OCCore,
		into downloadsDirectory: URL,
		alreadyMaterializedRelativePaths: Set<String> = [],
		publishProgress: ((Progress) -> Void)? = nil,
		onEntryMaterialized: ((String) -> Void)? = nil,
		cancellationToken: ZipDownloadCancellationToken? = nil,
		completion: @escaping (Result<[ZipLocalEntry], Error>) -> Void
	) -> ZipDownloadCancellationToken {
		let token = cancellationToken ?? ZipDownloadCancellationToken()
		ZipDebugLogging.log(plan: plan, context: "materializeArchiveEntries")

		guard plan.fileEntries.count > 0 else {
			ZipDebugLogging.log("materializeArchiveEntries: no files in plan — returning empty result")
			completion(.success([]))
			return token
		}

		do {
			try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
			// Gate all compress downloads/copies — including folder expansions — here so the
			// check cannot be skipped by session/resume call-site differences.
			let required = requiredFreeSpaceForCompress(
				plan: plan,
				downloadsDirectory: downloadsDirectory,
				alreadyMaterializedRelativePaths: alreadyMaterializedRelativePaths
			)
			try ensureEnoughDiskSpace(requiredBytes: required, at: downloadsDirectory)
		} catch {
			ZipDebugLogging.log(error: error, context: "materializeArchiveEntries.diskSpace")
			completion(.failure(error))
			return token
		}

		let progressTracker = ZipDownloadProgressTracker(entries: plan.fileEntries)
		publishProgress?(progressTracker.progress)
		token.track(progressTracker.progress)

		final class ObservationBox {
			var observations: [NSKeyValueObservation] = []
		}
		struct PendingDownload {
			let key: String
			let item: OCItem
			let destinationURL: URL
		}
		let observationBox = ObservationBox()
		var didFinish = false
		let finishLock = NSLock()
		var pendingKeys = Set(plan.fileEntries.map(\.archiveRelativePath))
		var localEntriesByKey: [String: ZipLocalEntry] = [:]
		var firstError: Error?
		var inFlightDownloads: [String: OCItem] = [:]
		var inFlightPartURLs: [String: URL] = [:]
		var pendingDownloads: [PendingDownload] = []
		var activeDownloadCount = 0
		var progressPollActive = false
		let maxConcurrent = max(1, maxConcurrentDownloads)

		func finish(_ result: Result<[ZipLocalEntry], Error>) {
			finishLock.lock()
			guard !didFinish else {
				finishLock.unlock()
				return
			}
			didFinish = true
			let parts = Array(inFlightPartURLs.values)
			inFlightDownloads.removeAll()
			inFlightPartURLs.removeAll()
			pendingDownloads.removeAll()
			activeDownloadCount = 0
			progressPollActive = false
			finishLock.unlock()
			observationBox.observations.removeAll()
			if case .failure = result {
				for partURL in parts {
					removeItemIfExists(at: partURL)
				}
			}
			completion(result)
		}

		token.setCancelHandler {
			ZipDebugLogging.log("materializeArchiveEntries: cancelled")
			finish(.failure(NSError(ocError: .cancelled)))
		}

		func markDone(key: String, entry: ZipLocalEntry?, error: Error?, releasedDownloadSlot: Bool = false) {
			var resultToFinish: Result<[ZipLocalEntry], Error>?
			var shouldNotifyMaterialized = false
			var shouldPump = false
			var partToRemove: URL?

			finishLock.lock()
			inFlightDownloads.removeValue(forKey: key)
			partToRemove = inFlightPartURLs.removeValue(forKey: key)
			if releasedDownloadSlot {
				activeDownloadCount = max(0, activeDownloadCount - 1)
				shouldPump = !didFinish && !token.isCancelled
			}
			if !didFinish {
				if let error {
					if firstError == nil {
						firstError = error
					}
				} else if let entry {
					localEntriesByKey[key] = entry
					progressTracker.markFinished(key: key)
					shouldNotifyMaterialized = true
				}

				pendingKeys.remove(key)
				if pendingKeys.isEmpty {
					if token.isCancelled {
						resultToFinish = .failure(NSError(ocError: .cancelled))
					} else if let firstError {
						resultToFinish = .failure(firstError)
					} else {
						let ordered = plan.fileEntries.compactMap { localEntriesByKey[$0.archiveRelativePath] }
						progressTracker.markAllFinished()
						ZipDebugLogging.log(localEntries: ordered, context: "materializeArchiveEntries.completed")
						resultToFinish = .success(ordered)
					}
				}
			}
			finishLock.unlock()

			// Incomplete downloads leave .part behind; successful finalize already moved it away.
			if entry == nil, let partToRemove {
				removeItemIfExists(at: partToRemove)
			}

			if shouldNotifyMaterialized {
				onEntryMaterialized?(key)
			}
			if let resultToFinish {
				finish(resultToFinish)
			} else if shouldPump {
				pumpDownloads()
			}
		}

		func attachProgress(for item: OCItem, key: String, fallback: Progress?) {
			guard let best = bestDownloadProgress(for: item, core: core, fallback: fallback) else {
				return
			}
			token.track(best)
			let newObservations = progressTracker.observe(best, key: key)
			if !newObservations.isEmpty {
				observationBox.observations.append(contentsOf: newObservations)
			}
		}

		func scheduleProgressPollIfNeeded() {
			finishLock.lock()
			let shouldStart = !progressPollActive && !didFinish && !inFlightDownloads.isEmpty
			if shouldStart {
				progressPollActive = true
			}
			finishLock.unlock()
			guard shouldStart else { return }

			func poll() {
				if token.isCancelled {
					return
				}

				finishLock.lock()
				let inflight = inFlightDownloads
				let finished = didFinish
				finishLock.unlock()

				if finished || inflight.isEmpty {
					finishLock.lock()
					progressPollActive = false
					finishLock.unlock()
					return
				}

				for (key, item) in inflight {
					attachProgress(for: item, key: key, fallback: nil)
				}

				DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
					poll()
				}
			}

			DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
				poll()
			}
		}

		func startDownload(_ pending: PendingDownload) {
			let key = pending.key
			let item = pending.item
			let destinationURL = pending.destinationURL
			let partURL = Self.partURL(for: destinationURL)
			let expectedSize = Int64(max(item.size, 0))

			if token.isCancelled {
				markDone(key: key, entry: nil, error: NSError(ocError: .cancelled), releasedDownloadSlot: true)
				return
			}

			removeItemIfExists(at: partURL)
			removeItemIfExists(at: destinationURL)

			ZipDebugLogging.log("materializeArchiveEntries: connection download \(Log.mask(key)) → \(Log.mask(partURL.path))")

			let eventTarget = OCEventTarget(ephermalEventHandlerBlock: { event, _ in
				if token.isCancelled {
					markDone(key: key, entry: nil, error: NSError(ocError: .cancelled), releasedDownloadSlot: true)
					return
				}
				if let error = event.error {
					ZipDebugLogging.log(error: error, context: "materializeArchiveEntries.download(\(Log.mask(key)))")
					markDone(key: key, entry: nil, error: error, releasedDownloadSlot: true)
					return
				}
				do {
					try finalizeDownloadedFile(
						partURL: partURL,
						destinationURL: destinationURL,
						eventFileURL: event.file?.url,
						expectedSize: expectedSize
					)
					ZipDebugLogging.log("materializeArchiveEntries: download finished \(Log.mask(key))")
					markDone(key: key, entry: ZipLocalEntry(archiveRelativePath: key, localURL: destinationURL), error: nil, releasedDownloadSlot: true)
				} catch {
					ZipDebugLogging.log(error: error, context: "materializeArchiveEntries.finalize(\(Log.mask(key)))")
					markDone(key: key, entry: nil, error: error, releasedDownloadSlot: true)
				}
			}, userInfo: nil, ephermalUserInfo: nil)

			guard let ocProgress = core.connection.downloadItem(item, to: partURL, options: nil, resultTarget: eventTarget) else {
				ZipDebugLogging.log("materializeArchiveEntries: downloadItem returned nil for \(Log.mask(key))")
				markDone(key: key, entry: nil, error: NSError(ocError: .internal), releasedDownloadSlot: true)
				return
			}

			finishLock.lock()
			inFlightDownloads[key] = item
			inFlightPartURLs[key] = partURL
			finishLock.unlock()

			// Request progress is often indeterminate; sized bytes live on the pipeline progress.
			let fallback = ocProgress.progress
			if let fallback {
				token.track(fallback)
			}
			attachProgress(for: item, key: key, fallback: fallback)
			scheduleProgressPollIfNeeded()
		}

		func pumpDownloads() {
			var toStart: [PendingDownload] = []
			finishLock.lock()
			while activeDownloadCount < maxConcurrent, !pendingDownloads.isEmpty, !didFinish, !token.isCancelled {
				toStart.append(pendingDownloads.removeFirst())
				activeDownloadCount += 1
			}
			let remaining = pendingDownloads.count
			let active = activeDownloadCount
			finishLock.unlock()

			if !toStart.isEmpty {
				ZipDebugLogging.log("materializeArchiveEntries: starting \(toStart.count) download(s); active=\(active) queued=\(remaining) max=\(maxConcurrent)")
			}
			for pending in toStart {
				startDownload(pending)
			}
		}

		DispatchQueue.global(qos: .userInitiated).async {
			ZipDebugLogging.log("materializeArchiveEntries: maxConcurrentDownloads=\(maxConcurrent)")

			for entry in plan.fileEntries {
				if token.isCancelled {
					finish(.failure(NSError(ocError: .cancelled)))
					return
				}

				let key = entry.archiveRelativePath
				let item = resolvedItem(entry.item, core: core)
				guard item.type == .file else {
					ZipDebugLogging.log("materializeArchiveEntries: skipping non-file \(Log.mask(key))")
					markDone(key: key, entry: nil, error: nil)
					continue
				}

				let destinationURL = destinationURL(forRelativePath: key, in: downloadsDirectory)
				let expectedSize = Int64(max(item.size, 0))
				// Never treat .part / truncated files as resume-complete.
				removeItemIfExists(at: partURL(for: destinationURL))

				if alreadyMaterializedRelativePaths.contains(key) || fileIsComplete(at: destinationURL, expectedSize: expectedSize) {
					if fileIsComplete(at: destinationURL, expectedSize: expectedSize) {
						ZipDebugLogging.log("materializeArchiveEntries: resume hit \(Log.mask(key))")
						markDone(key: key, entry: ZipLocalEntry(archiveRelativePath: key, localURL: destinationURL), error: nil)
						continue
					}
					// Stale resume marker without a complete file — fall through to re-materialize.
					ZipDebugLogging.log("materializeArchiveEntries: stale resume marker for \(Log.mask(key)) — re-downloading")
				}

				if let localURL = localFileURL(for: item, core: core) {
					do {
						try prepareDestination(destinationURL)
						removeItemIfExists(at: destinationURL)
						try FileManager.default.copyItem(at: localURL, to: destinationURL)
						core.registerUsage(of: item, completionHandler: nil)
						ZipDebugLogging.log("materializeArchiveEntries: copied local \(Log.mask(key))")
						markDone(key: key, entry: ZipLocalEntry(archiveRelativePath: key, localURL: destinationURL), error: nil)
					} catch {
						ZipDebugLogging.log(error: error, context: "materializeArchiveEntries.copy(\(Log.mask(key)))")
						markDone(key: key, entry: nil, error: error)
					}
					continue
				}

				do {
					try prepareDestination(destinationURL)
				} catch {
					markDone(key: key, entry: nil, error: error)
					continue
				}

				finishLock.lock()
				pendingDownloads.append(PendingDownload(key: key, item: item, destinationURL: destinationURL))
				finishLock.unlock()
			}

			pumpDownloads()
		}

		return token
	}

	/// Prefers sized HTTP pipeline progress (same source file cells use), then the request Progress stub.
	private static func bestDownloadProgress(for item: OCItem, core: OCCore, fallback: Progress? = nil) -> Progress? {
		guard let localID = item.localID else {
			return fallback
		}

		if let live = core.connection.liveDownloadTransferProgress(forItemLocalID: localID) as Progress?,
		   !live.isFinished,
		   !live.isCancelled {
			return live
		}

		if let fallback, !fallback.isFinished, !fallback.isCancelled {
			return fallback
		}
		return nil
	}

	/// Materializes a single item (e.g. zip for decompress) into `destinationURL`.
	@discardableResult
	static func materializeItem(
		_ item: OCItem,
		core: OCCore,
		to destinationURL: URL,
		alreadyMaterializedRelativePaths: Set<String> = [],
		publishProgress: ((Progress) -> Void)? = nil,
		cancellationToken: ZipDownloadCancellationToken? = nil,
		completion: @escaping (Result<URL, Error>) -> Void
	) -> ZipDownloadCancellationToken {
		let token = cancellationToken ?? ZipDownloadCancellationToken()
		let resolved = resolvedItem(item, core: core)
		let relativePath = destinationURL.lastPathComponent
		let plan = ZipArchivePlan(
			fileEntries: [ZipArchiveEntry(item: resolved, archiveRelativePath: relativePath)],
			emptyFolderPaths: [],
			folderItems: []
		)
		let downloadsDir = destinationURL.deletingLastPathComponent()
		var already = alreadyMaterializedRelativePaths
		let expectedSize = Int64(max(resolved.size, 0))
		removeItemIfExists(at: partURL(for: destinationURL))
		if fileIsComplete(at: destinationURL, expectedSize: expectedSize) {
			already.insert(relativePath)
		} else {
			removeItemIfExists(at: destinationURL)
		}

		_ = materializeArchiveEntries(
			plan,
			core: core,
			into: downloadsDir,
			alreadyMaterializedRelativePaths: already,
			publishProgress: publishProgress,
			cancellationToken: token
		) { result in
			switch result {
			case .failure(let error):
				completion(.failure(error))
			case .success(let entries):
				if let url = entries.first?.localURL {
					completion(.success(url))
				} else {
					completion(.failure(NSError(ocError: .internal)))
				}
			}
		}
		return token
	}

	private static func destinationURL(forRelativePath relativePath: String, in downloadsDirectory: URL) -> URL {
		let parts = relativePath.split(separator: "/").map(String.init)
		guard !parts.isEmpty else {
			return downloadsDirectory
		}
		var url = downloadsDirectory
		for (index, part) in parts.enumerated() {
			let isLast = index == parts.count - 1
			url = url.appendingPathComponent(part, isDirectory: !isLast)
		}
		return url
	}

	private static func prepareDestination(_ destinationURL: URL) throws {
		let parent = destinationURL.deletingLastPathComponent()
		try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
	}

	private static func fileExistsNonEmpty(at url: URL) -> Bool {
		guard let size = fileSize(at: url) else { return false }
		return size > 0
	}

	private static func fileSize(at url: URL) -> Int64? {
		guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
		      let size = attrs[.size] as? NSNumber else {
			return nil
		}
		return size.int64Value
	}

	/// Partial-download sidecar path (`file.ext` → `file.ext.part`).
	static func partURL(for destinationURL: URL) -> URL {
		URL(fileURLWithPath: destinationURL.path + ".part", isDirectory: false)
	}

	/// True when a finalized file is present and, if `expectedSize > 0`, matches that size.
	static func fileIsComplete(at url: URL, expectedSize: Int64) -> Bool {
		guard let size = fileSize(at: url), size > 0 else { return false }
		if expectedSize > 0 {
			return size == expectedSize
		}
		return true
	}

	static func removeItemIfExists(at url: URL) {
		guard FileManager.default.fileExists(atPath: url.path) else { return }
		try? FileManager.default.removeItem(at: url)
	}

	/// Removes stray `*.part` files under `directory` (non-recursive top-level only via enumerator).
	private static func removePartFiles(under directory: URL) {
		let fileManager = FileManager.default
		guard let enumerator = fileManager.enumerator(
			at: directory,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		) else { return }

		for case let fileURL as URL in enumerator {
			if fileURL.pathExtension == "part" || fileURL.lastPathComponent.hasSuffix(".part") {
				try? fileManager.removeItem(at: fileURL)
			}
		}
	}

	/// Promotes a finished `.part` (or alternate download URL) to the final destination.
	private static func finalizeDownloadedFile(
		partURL: URL,
		destinationURL: URL,
		eventFileURL: URL?,
		expectedSize: Int64
	) throws {
		let fileManager = FileManager.default
		var sourceURL = partURL

		if let eventFileURL,
		   eventFileURL.standardizedFileURL != partURL.standardizedFileURL,
		   eventFileURL.standardizedFileURL != destinationURL.standardizedFileURL,
		   fileManager.fileExists(atPath: eventFileURL.path) {
			removeItemIfExists(at: partURL)
			sourceURL = eventFileURL
		}

		guard fileIsComplete(at: sourceURL, expectedSize: expectedSize) else {
			removeItemIfExists(at: sourceURL)
			throw NSError(ocError: .internal)
		}

		if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
			removeItemIfExists(at: destinationURL)
			try fileManager.moveItem(at: sourceURL, to: destinationURL)
		}

		guard fileIsComplete(at: destinationURL, expectedSize: expectedSize) else {
			removeItemIfExists(at: destinationURL)
			throw NSError(ocError: .internal)
		}
	}

	/// Aggregates per-file download Progress into one size-weighted Progress for UI.
	private final class ZipDownloadProgressTracker {
		let progress: Progress
		private let weightsByKey: [String: Int64]
		private var fractionsByKey: [String: Double] = [:]
		private var observedProgressIDs = Set<ObjectIdentifier>()
		private let lock = NSLock()

		init(entries: [ZipArchiveEntry]) {
			var weights: [String: Int64] = [:]
			for entry in entries {
				weights[entry.archiveRelativePath] = max(Int64(entry.item.size), 1)
			}
			self.weightsByKey = weights
			let total = max(weights.values.reduce(Int64(0), +), 1)
			self.progress = Progress(totalUnitCount: total)
		}

		func observe(_ source: Progress, key: String) -> [NSKeyValueObservation] {
			lock.lock()
			let id = ObjectIdentifier(source)
			guard !observedProgressIDs.contains(id) else {
				lock.unlock()
				return []
			}
			observedProgressIDs.insert(id)
			lock.unlock()

			let publish: (Progress) -> Void = { [weak self] observed in
				self?.update(key: key, fraction: Self.fraction(of: observed))
			}
			return [
				source.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in publish(progress) },
				source.observe(\.completedUnitCount, options: [.new]) { progress, _ in publish(progress) },
				source.observe(\.totalUnitCount, options: [.new]) { progress, _ in publish(progress) }
			]
		}

		func markFinished(key: String) {
			update(key: key, fraction: 1)
		}

		func markAllFinished() {
			progress.completedUnitCount = progress.totalUnitCount
		}

		private static func fraction(of observed: Progress) -> Double {
			if observed.totalUnitCount > 0 {
				return min(1, max(0, Double(observed.completedUnitCount) / Double(observed.totalUnitCount)))
			}
			return min(1, max(0, observed.fractionCompleted))
		}

		private func update(key: String, fraction: Double) {
			lock.lock()
			let clamped = min(1, max(0, fraction))
			if let existing = fractionsByKey[key], existing >= clamped, clamped < 1 {
				lock.unlock()
				return
			}
			fractionsByKey[key] = clamped
			let completed = weightsByKey.reduce(Int64(0)) { partial, pair in
				let fraction = fractionsByKey[pair.key] ?? 0
				return partial + Int64(Double(pair.value) * fraction)
			}
			lock.unlock()
			progress.completedUnitCount = min(progress.totalUnitCount, max(0, completed))
		}
	}

	private static func localFileURL(for item: OCItem, core: OCCore) -> URL? {
		let resolved = resolvedItem(item, core: core)
		guard let url = core.localCopy(of: resolved) else {
			return nil
		}
		guard FileManager.default.fileExists(atPath: url.path) else {
			ZipDebugLogging.log("localFileURL: missing on disk path=\(Log.mask(url.path))")
			return nil
		}
		return url
	}

	private static func resolvedItem(_ item: OCItem, core: OCCore) -> OCItem {
		if let location = item.location, let cachedItem = try? core.cachedItem(at: location) {
			return cachedItem
		}

		if let name = item.name, name.isEmpty == false, let parent = item.parentItem(from: core) {
			let isDirectory = item.type == .collection
			if let cachedItem = try? core.cachedItem(inParent: parent, withName: name, isDirectory: isDirectory) {
				return cachedItem
			}
		}

		return item
	}

	private struct FolderContents {
		let fileEntries: [ZipArchiveEntry]
		let emptyFolderPaths: [String]
		let folderItems: [OCItem]
	}

	private static func deduplicatedItems(_ items: [OCItem]) -> [OCItem] {
		var seen = Set<String>()
		var unique: [OCItem] = []
		for item in items {
			guard let localID = item.localID as String?, seen.insert(localID).inserted else { continue }
			unique.append(item)
		}
		return unique
	}

	private static func collectFolderContents(folderItem: OCItem, rootItem: OCItem, core: OCCore, completion: @escaping (Result<FolderContents, Error>) -> Void) {
		guard let location = folderItem.location else {
			ZipDebugLogging.log("collectFolderContents: folder has no location name=\(Log.mask(folderItem.name ?? "nil"))")
			completion(.failure(NSError(ocError: .itemNotFound)))
			return
		}

		let resolvedFolder = resolvedItem(folderItem, core: core)

		ZipDebugLogging.log("collectFolderContents: PROPFIND depth=1 at \(Log.mask(location.path))")
		_ = core.connection.retrieveItemList(at: location, depth: 1, options: nil) { error, foundItems in
			if let error = error {
				ZipDebugLogging.log(error: error, context: "collectFolderContents.retrieveItemList(\(Log.mask(folderItem.name ?? "nil")))")
				completion(.failure(error))
				return
			}

			let children = (foundItems ?? []).filter { child in
				isChild(child, of: folderItem)
			}
			ZipDebugLogging.log("collectFolderContents: folder \(Log.mask(folderItem.name ?? "nil")) returned \(foundItems?.count ?? 0) item(s), \(children.count) child(ren)")

			if children.isEmpty {
				if let relativePath = archiveRelativePath(for: folderItem, under: rootItem) {
					ZipDebugLogging.log("collectFolderContents: treating \(Log.mask(relativePath)) as empty folder")
					completion(.success(FolderContents(fileEntries: [], emptyFolderPaths: [relativePath], folderItems: [resolvedFolder])))
				} else {
					ZipDebugLogging.log("collectFolderContents: no children and no relative path for \(Log.mask(folderItem.name ?? "nil"))")
					completion(.success(FolderContents(fileEntries: [], emptyFolderPaths: [], folderItems: [resolvedFolder])))
				}
				return
			}

			var fileEntries: [ZipArchiveEntry] = []
			for fileItem in children where fileItem.type == .file {
				let resolvedFile = resolvedItem(fileItem, core: core)
				if let relativePath = archiveRelativePath(for: resolvedFile, under: rootItem) {
					fileEntries.append(ZipArchiveEntry(item: resolvedFile, archiveRelativePath: relativePath))
					ZipDebugLogging.log("collectFolderContents: discovered file \(Log.mask(relativePath))")
				} else {
					ZipDebugLogging.log("collectFolderContents: could not resolve relative path for file \(Log.mask(fileItem.name ?? "nil"))")
				}
			}

			let subfolders = children.filter { $0.type == .collection }
			ZipDebugLogging.log("collectFolderContents: recursing into \(subfolders.count) subfolder(s) from \(Log.mask(folderItem.name ?? "nil"))")
			collectSubfolderContents(
				subfolders,
				rootItem: rootItem,
				core: core,
				accumulatedFiles: fileEntries,
				accumulatedEmptyFolders: [],
				accumulatedFolders: [resolvedFolder],
				completion: completion
			)
		}
	}

	private static func collectSubfolderContents(
		_ subfolders: [OCItem],
		rootItem: OCItem,
		core: OCCore,
		accumulatedFiles: [ZipArchiveEntry],
		accumulatedEmptyFolders: [String],
		accumulatedFolders: [OCItem],
		completion: @escaping (Result<FolderContents, Error>) -> Void
	) {
		guard !subfolders.isEmpty else {
			completion(.success(FolderContents(
				fileEntries: accumulatedFiles,
				emptyFolderPaths: accumulatedEmptyFolders,
				folderItems: accumulatedFolders
			)))
			return
		}

		let maxConcurrent = max(1, maxConcurrentFolderEnumerations)
		let lock = NSLock()
		var pending = subfolders
		var active = 0
		var didFinish = false
		var firstError: Error?
		var mergedFiles = accumulatedFiles
		var mergedEmptyFolders = accumulatedEmptyFolders
		var mergedFolders = accumulatedFolders

		func finish(_ result: Result<FolderContents, Error>) {
			lock.lock()
			guard !didFinish else {
				lock.unlock()
				return
			}
			didFinish = true
			lock.unlock()
			completion(result)
		}

		func pump() {
			var toStart: [OCItem] = []
			lock.lock()
			while active < maxConcurrent, !pending.isEmpty, !didFinish, firstError == nil {
				toStart.append(pending.removeFirst())
				active += 1
			}
			lock.unlock()

			for subfolder in toStart {
				collectFolderContents(folderItem: subfolder, rootItem: rootItem, core: core) { result in
					var shouldPump = false
					var finishResult: Result<FolderContents, Error>?

					lock.lock()
					active = max(0, active - 1)
					if !didFinish {
						switch result {
						case .failure(let error):
							if firstError == nil {
								firstError = error
							}
							pending.removeAll()
							finishResult = .failure(error)
						case .success(let contents):
							mergedFiles.append(contentsOf: contents.fileEntries)
							mergedEmptyFolders.append(contentsOf: contents.emptyFolderPaths)
							mergedFolders.append(contentsOf: contents.folderItems)
							if pending.isEmpty && active == 0 {
								if let firstError {
									finishResult = .failure(firstError)
								} else {
									finishResult = .success(FolderContents(
										fileEntries: mergedFiles,
										emptyFolderPaths: mergedEmptyFolders,
										folderItems: mergedFolders
									))
								}
							} else {
								shouldPump = firstError == nil
							}
						}
					}
					lock.unlock()

					if let finishResult {
						finish(finishResult)
					} else if shouldPump {
						pump()
					}
				}
			}
		}

		ZipDebugLogging.log("collectSubfolderContents: \(subfolders.count) sibling(s), maxConcurrent=\(maxConcurrent)")
		pump()
	}

	// MARK: - Disk space

	/// FS overhead reserved beyond payload estimates (temp files, zip metadata, directory entries).
	private static let diskSpaceOverheadBytes: Int64 = 32 * 1024 * 1024

	/// Prefer Important Usage capacity (Apple’s guidance for downloads); fall back to general available /
	/// `attributesOfFileSystem` free size (more reliable on some device paths).
	private static func availableDiskSpace(at url: URL) -> Int64? {
		func capacity(from probeURL: URL) -> Int64? {
			if let values = try? probeURL.resourceValues(forKeys: [
				.volumeAvailableCapacityForImportantUsageKey,
				.volumeAvailableCapacityKey
			]) {
				if let important = values.volumeAvailableCapacityForImportantUsage, important >= 0 {
					return important
				}
				if let available = values.volumeAvailableCapacity {
					return Int64(available)
				}
			}

			let path = probeURL.path.isEmpty ? "/" : probeURL.path
			if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
			   let free = attrs[.systemFreeSize] as? NSNumber {
				return free.int64Value
			}
			return nil
		}

		if let value = capacity(from: url) {
			return value
		}

		var parent = url
		for _ in 0..<4 {
			let next = parent.deletingLastPathComponent()
			if next.path == parent.path { break }
			parent = next
			if let value = capacity(from: parent) {
				return value
			}
		}

		if let home = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
		   let value = capacity(from: home) {
			return value
		}
		return nil
	}

	/// Sum of PROPFIND file sizes in the plan (folders are already expanded into file entries).
	private static func contentByteSize(for plan: ZipArchivePlan) -> Int64 {
		plan.fileEntries.reduce(Int64(0)) { partial, entry in
			partial + max(Int64(entry.item.size), 0)
		}
	}

	/// Bytes still needed in `downloadsDirectory` before materialize finishes.
	private static func remainingMaterializeBytes(
		for plan: ZipArchivePlan,
		downloadsDirectory: URL,
		alreadyMaterializedRelativePaths: Set<String> = []
	) -> Int64 {
		var total: Int64 = 0
		for entry in plan.fileEntries {
			let key = entry.archiveRelativePath
			let destination = destinationURL(forRelativePath: key, in: downloadsDirectory)
			if alreadyMaterializedRelativePaths.contains(key) || fileIsComplete(at: destination, expectedSize: Int64(max(entry.item.size, 0))) {
				continue
			}
			total += max(Int64(entry.item.size), 0)
		}
		return total
	}

	/// Free space required before compress materialize.
	/// Pipeline keeps downloads, then writes the zip → peak ≈ remaining + content (no staging copy).
	static func requiredFreeSpaceForCompress(
		plan: ZipArchivePlan,
		downloadsDirectory: URL,
		alreadyMaterializedRelativePaths: Set<String> = []
	) -> Int64 {
		let contentBytes = contentByteSize(for: plan)
		let remainingBytes = remainingMaterializeBytes(
			for: plan,
			downloadsDirectory: downloadsDirectory,
			alreadyMaterializedRelativePaths: alreadyMaterializedRelativePaths
		)
		// Unknown remote sizes (all zeros) — still reserve overhead so tiny free space fails early.
		let required = remainingBytes + contentBytes + diskSpaceOverheadBytes
		return max(required, diskSpaceOverheadBytes)
	}

	/// Free space before downloading/copying a zip for decompress (extract size unknown → ~2× zip).
	static func requiredFreeSpaceForDecompressDownload(zipByteSize: Int64, zipAlreadyOnDisk: Bool) -> Int64 {
		let zipSize = max(zipByteSize, 0)
		let downloadBytes = zipAlreadyOnDisk ? Int64(0) : zipSize
		let extractEstimate = max(zipSize * 2, zipSize)
		return downloadBytes + extractEstimate + diskSpaceOverheadBytes
	}

	static func ensureEnoughDiskSpace(requiredBytes: Int64, at url: URL) throws {
		ZipDebugLogging.log(
			"ensureEnoughDiskSpace: checking required=\(ZipDebugLogging.formattedBytes(requiredBytes)) at \(Log.mask(url.path))"
		)
		guard let available = availableDiskSpace(at: url) else {
			ZipDebugLogging.log("ensureEnoughDiskSpace: capacity unknown — treating as insufficient")
			throw ZipArchiveError.insufficientStorage
		}
		ZipDebugLogging.log(
			"ensureEnoughDiskSpace: available=\(ZipDebugLogging.formattedBytes(available))"
		)
		if available < requiredBytes {
			ZipDebugLogging.log(
				"ensureEnoughDiskSpace: REJECTED required=\(ZipDebugLogging.formattedBytes(requiredBytes)) available=\(ZipDebugLogging.formattedBytes(available))"
			)
			throw ZipArchiveError.insufficientStorage
		}
	}

	/// Ensures `downloads/` (zip root) has empty folders and no stray `.part` files, then is ready to zip in place.
	/// Files are already laid out under `zipRootURL` by materialize — no staging copy.
	static func prepareZipRoot(plan: ZipArchivePlan, localEntries: [ZipLocalEntry], at zipRootURL: URL, progress: Progress) throws {
		ZipDebugLogging.log(plan: plan, context: "prepareZipRoot")
		ZipDebugLogging.log(localEntries: localEntries, context: "prepareZipRoot")
		ZipDebugLogging.log(url: zipRootURL, context: "prepareZipRoot.zipRootURL")

		let fileManager = FileManager.default
		try fileManager.createDirectory(at: zipRootURL, withIntermediateDirectories: true, attributes: [
			.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
		])
		removePartFiles(under: zipRootURL)

		let standardizedRoot = zipRootURL.standardizedFileURL.path
		for entry in localEntries {
			let entryPath = entry.localURL.standardizedFileURL.path
			guard entryPath == standardizedRoot || entryPath.hasPrefix(standardizedRoot + "/") else {
				ZipDebugLogging.log("prepareZipRoot: entry outside zip root relativePath=\(Log.mask(entry.archiveRelativePath)) path=\(Log.mask(entryPath))")
				throw NSError(ocError: .internal)
			}
			guard fileExistsNonEmpty(at: entry.localURL) else {
				ZipDebugLogging.log("prepareZipRoot: missing materialized file \(Log.mask(entry.archiveRelativePath))")
				throw NSError(ocError: .internal)
			}
		}

		progress.totalUnitCount = max(Int64(plan.emptyFolderPaths.count + 1), 1)
		progress.completedUnitCount = 0
		ZipDebugLogging.log("prepareZipRoot: creating \(plan.emptyFolderPaths.count) empty folder(s); \(localEntries.count) file(s) already in place")

		for emptyFolderPath in plan.emptyFolderPaths {
			if progress.isCancelled {
				throw NSError(ocError: .cancelled)
			}
			let destinationURL = zipRootURL.appendingPathComponent(emptyFolderPath, isDirectory: true)
			try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: [
				.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
			])
			ZipDebugLogging.log("prepareZipRoot: created empty folder \(Log.mask(emptyFolderPath))")
			progress.completedUnitCount += 1
		}
	}

	static func createArchive(at archiveURL: URL, fromDirectory directoryURL: URL, progress: Progress) throws {
		ZipDebugLogging.log(url: directoryURL, context: "createArchive.directoryURL")
		ZipDebugLogging.log(url: archiveURL, context: "createArchive.archiveURL(before)")

		let fileManager = FileManager.default
		try? fileManager.removeItem(at: archiveURL)

		progress.localizedDescription = HCL10n.ZipAction.Progress.compressing

		let zipProgress = Progress(totalUnitCount: 1, parent: progress, pendingUnitCount: 1)
		let startTime = Date()
		ZipDebugLogging.log("createArchive: starting zip of directory (this may take a while for large archives)")
		do {
			try fileManager.zipItem(at: directoryURL, to: archiveURL, shouldKeepParent: false, compressionMethod: .deflate, progress: zipProgress)
		} catch {
			if isInsufficientStorageError(error) {
				throw ZipArchiveError.insufficientStorage
			}
			throw error
		}
		progress.completedUnitCount = progress.totalUnitCount
		let elapsed = Date().timeIntervalSince(startTime)
		let archiveSize = (try? fileManager.attributesOfItem(atPath: archiveURL.path)[.size] as? NSNumber)?.int64Value ?? 0
		ZipDebugLogging.log("createArchive: done elapsed=\(String(format: "%.1f", elapsed))s outputSize=\(ZipDebugLogging.formattedBytes(archiveSize))")
		ZipDebugLogging.log(url: archiveURL, context: "createArchive.archiveURL(after)")
	}

	static func extractArchive(at archiveURL: URL, to destinationURL: URL, progress: Progress) throws {
		let profile = ZipDebugLogging.ProfileScope(
			"extractArchive",
			extra: "archive=\(Log.mask(archiveURL.lastPathComponent))"
		)
		defer { profile.end() }

		let archiveFileSize = (try? FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? NSNumber)?.int64Value ?? 0
		ZipDebugLogging.log("extractArchive: archiveSize=\(ZipDebugLogging.formattedBytes(archiveFileSize)) path=\(Log.mask(archiveURL.lastPathComponent))")
		ZipDebugLogging.log(url: archiveURL, context: "extractArchive.archiveURL")
		ZipDebugLogging.log(url: destinationURL, context: "extractArchive.destinationURL(before)")

		if containsEncryptedEntries(at: archiveURL) {
			profile.mark("encryptedScan", extra: "result=encrypted")
			ZipDebugLogging.log("extractArchive: encrypted entries detected")
			throw ZipArchiveError.encryptedArchive
		}
		profile.mark("encryptedScan", extra: "result=clear size=\(ZipDebugLogging.formattedBytes(archiveFileSize))")

		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: destinationURL.path) {
			ZipDebugLogging.log("extractArchive: removing existing destination at \(Log.mask(destinationURL.path))")
			try fileManager.removeItem(at: destinationURL)
		}
		do {
			try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: [
				.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
			])
		} catch {
			if isInsufficientStorageError(error) {
				throw ZipArchiveError.insufficientStorage
			}
			throw error
		}
		ZipDebugLogging.log(url: destinationURL, context: "extractArchive.destinationURL(afterCreate)")

		guard let archive = Archive(url: archiveURL, accessMode: .read) else {
			ZipDebugLogging.log("extractArchive: failed to open archive at \(Log.mask(archiveURL.path))")
			throw ZipArchiveError.corruptedArchive
		}

		let rawEntries = Array(archive)
		profile.mark("openAndEnumerate", extra: "rawEntries=\(rawEntries.count)")
		ZipDebugLogging.log("extractArchive: archive contains \(rawEntries.count) raw entr\(rawEntries.count == 1 ? "y" : "ies")")

		for (index, entry) in rawEntries.enumerated() {
			let decoded = decodedEntryPath(entry)
			ZipDebugLogging.log("extractArchive.rawEntry[\(index)]: path=\(Log.mask(decoded)) flaggedPath=\(Log.mask(entry.path)) type=\(entry.type)")
		}

		// sanitizedArchiveEntryPath rejects any path with "..", ".", leading/trailing slashes
		// or empty components, so appending to destinationURL is always safe — no further
		// containment check is needed or reliable across iOS symlink aliases (/var vs /private/var).
		var entries = rawEntries.filter { sanitizedArchiveEntryPath(decodedEntryPath($0)) != nil }
		let skippedCount = rawEntries.count - entries.count
		if skippedCount > 0 {
			ZipDebugLogging.log("extractArchive: skipped \(skippedCount) unsafe/empty entr\(skippedCount == 1 ? "y" : "ies")")
		}

		if rawEntries.isEmpty {
			ZipDebugLogging.log("extractArchive: archive contains no readable entries")
			throw ZipArchiveError.corruptedArchive
		}

		if entries.isEmpty {
			ZipDebugLogging.log("extractArchive: no entries with supported names remain after filtering")
			throw ZipArchiveError.unsupportedEntryNames
		}

		// Directories first, then by depth so parents always exist before children
		entries.sort { lhs, rhs in
			if lhs.type != rhs.type { return lhs.type == .directory }
			return decodedEntryPath(lhs).split(separator: "/").count < decodedEntryPath(rhs).split(separator: "/").count
		}
		profile.mark("filterAndSort", extra: "extractable=\(entries.count) skipped=\(skippedCount)")

		let extractRoot = extractRootURL(for: entries, archiveURL: archiveURL, destinationURL: destinationURL)
		if extractRoot.standardizedFileURL != destinationURL.standardizedFileURL {
			do {
				try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true, attributes: [
					.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
				])
			} catch {
				if isInsufficientStorageError(error) {
					throw ZipArchiveError.insufficientStorage
				}
				throw error
			}
			ZipDebugLogging.log(url: extractRoot, context: "extractArchive.extractRoot(wrapped)")
		}

		progress.localizedDescription = HCL10n.ZipAction.Progress.decompressing
		progress.totalUnitCount = max(Int64(entries.count), 1)
		progress.completedUnitCount = 0

		if entries.isEmpty {
			ZipDebugLogging.log("extractArchive: no extractable entries remain after filtering")
		}

		var extractedCount = 0
		var skippedDuringExtractCount = 0
		var extractBytes: Int64 = 0
		let extractLoopStart = CFAbsoluteTimeGetCurrent()
		var lastProgressLog = extractLoopStart

		for (index, entry) in entries.enumerated() {
			if progress.isCancelled {
				ZipDebugLogging.log("extractArchive: cancelled at entry \(index + 1)/\(entries.count)")
				throw NSError(ocError: .cancelled)
			}

			guard let relativePath = sanitizedArchiveEntryPath(decodedEntryPath(entry)) else {
				skippedDuringExtractCount += 1
				ZipDebugLogging.log("extractArchive: skipping entry[\(index)] path=\(Log.mask(decodedEntryPath(entry))) reason=invalidSanitizedPath")
				continue
			}

			// Build the URL one component at a time so Foundation handles encoding correctly
			let entryURL: URL = relativePath
				.split(separator: "/")
				.map(String.init)
				.reduce(extractRoot) { url, component in
					url.appendingPathComponent(component)
				}

			ZipDebugLogging.log("extractArchive: entry[\(index)] relativePath=\(Log.mask(relativePath)) type=\(entry.type) -> \(Log.mask(entryURL.path))")

			removeItemIfExists(at: entryURL)
			let entryUncompressedSize = entry.uncompressedSize
			ZipDebugLogging.log("extractArchive: [\(index + 1)/\(entries.count)] extracting \(Log.mask(relativePath)) uncompressedSize=\(ZipDebugLogging.formattedBytes(Int64(entryUncompressedSize)))")
			let entryStart = Date()
			do {
				_ = try archive.extract(entry, to: entryURL)
			} catch {
				ZipDebugLogging.log(error: error, context: "extractArchive.extract(\(Log.mask(relativePath)))")
				if isInsufficientStorageError(error) {
					throw ZipArchiveError.insufficientStorage
				}
				throw ZipArchiveError.corruptedArchive
			}
			extractedCount += 1
			extractBytes += Int64(entryUncompressedSize)
			let entryElapsed = Date().timeIntervalSince(entryStart)
			ZipDebugLogging.log("extractArchive: [\(index + 1)/\(entries.count)] done elapsed=\(String(format: "%.2f", entryElapsed))s path=\(Log.mask(relativePath))")

			progress.completedUnitCount = Int64(index + 1)

			let now = CFAbsoluteTimeGetCurrent()
			let isLast = index + 1 == entries.count
			let slowEntry = entryElapsed >= 0.5
			if isLast || slowEntry || (index + 1) % 25 == 0 || (now - lastProgressLog) >= 5.0 {
				let loopElapsed = now - extractLoopStart
				let rate = loopElapsed > 0 ? Double(extractBytes) / loopElapsed : 0
				ZipDebugLogging.log(
					"⏱ PROFILE mark extractArchive.extractProgress \(index + 1)/\(entries.count) extracted=\(extractedCount) bytes=\(ZipDebugLogging.formattedBytes(extractBytes)) rate=\(ZipDebugLogging.formattedBytes(Int64(rate)))/s lastEntry=\(String(format: "%.2f", entryElapsed))s"
				)
				lastProgressLog = now
			}
		}

		profile.mark(
			"extractLoop",
			extra: "extracted=\(extractedCount) skipped=\(skippedDuringExtractCount) bytes=\(ZipDebugLogging.formattedBytes(extractBytes))"
		)

		ZipDebugLogging.log("extractArchive: finished extracted=\(extractedCount) skippedDuringExtract=\(skippedDuringExtractCount) destination=\(Log.mask(extractRoot.path))")

		if extractedCount == 0, entries.isEmpty == false {
			ZipDebugLogging.log("extractArchive: no entries were extracted")
			throw ZipArchiveError.unsupportedEntryNames
		}
	}

	/// Single root-level file → extract into `destinationURL`.
	/// Multiple files or any nested folder → extract into a folder named after the archive.
	private static func extractRootURL(for entries: [Entry], archiveURL: URL, destinationURL: URL) -> URL {
		var fileCount = 0
		var hasNestedFolders = false

		for entry in entries {
			guard let relativePath = sanitizedArchiveEntryPath(decodedEntryPath(entry)) else {
				continue
			}
			if entry.type == .directory || relativePath.contains("/") {
				hasNestedFolders = true
			}
			if entry.type != .directory {
				fileCount += 1
			}
		}

		guard shouldWrapExtractedContents(fileCount: fileCount, hasNestedFolders: hasNestedFolders) else {
			ZipDebugLogging.log("extractArchive: single-file archive — extracting into destination root")
			return destinationURL
		}

		let containerName = suggestedExtractContainerName(fromArchiveName: archiveURL.lastPathComponent)
		ZipDebugLogging.log("extractArchive: wrapping into container \(Log.mask(containerName)) fileCount=\(fileCount) hasNestedFolders=\(hasNestedFolders)")
		return destinationURL.appendingPathComponent(containerName, isDirectory: true)
	}

	private static func shouldWrapExtractedContents(fileCount: Int, hasNestedFolders: Bool) -> Bool {
		fileCount > 1 || hasNestedFolders
	}

	private static func suggestedExtractContainerName(fromArchiveName archiveName: String) -> String {
		let trimmed = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
		let baseName = (trimmed as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
		if baseName.isEmpty {
			return "Archive"
		}
		return baseName
	}

	private static func containsEncryptedEntries(at archiveURL: URL) -> Bool {
		guard let data = try? Data(contentsOf: archiveURL, options: [.mappedIfSafe]), !data.isEmpty else {
			return false
		}
		return zipDataContainsEncryptedEntries(data)
	}

	private static func zipDataContainsEncryptedEntries(_ data: Data) -> Bool {
		let bytes = [UInt8](data)
		var index = 0
		while index + 4 <= bytes.count {
			if bytes[index] == 0x50, bytes[index + 1] == 0x4b {
				if bytes[index + 2] == 0x01, bytes[index + 3] == 0x02, index + 10 <= bytes.count {
					let flag = UInt16(bytes[index + 8]) | (UInt16(bytes[index + 9]) << 8)
					if flag & 0x1 != 0 {
						return true
					}
				} else if bytes[index + 2] == 0x03, bytes[index + 3] == 0x04, index + 8 <= bytes.count {
					let flag = UInt16(bytes[index + 6]) | (UInt16(bytes[index + 7]) << 8)
					if flag & 0x1 != 0 {
						return true
					}
				}
			}
			index += 1
		}
		return false
	}

	private static func isInsufficientStorageError(_ error: Error) -> Bool {
		ZipArchiveError.classify(error, for: .decompress) == .insufficientStorage
	}

	/// Decode a ZIP entry path the way macOS Archive Utility does: prefer UTF-8 when the
	/// raw filename bytes are valid UTF-8, even if the Language Encoding Flag (bit 11) is
	/// unset. ZIPFoundation's `entry.path` falls back to CP437 without that flag, which
	/// turns UTF-8 names into mojibake (e.g. NFD `Hình` → `Hi╠Çnh`).
	///
	/// Always returns NFC (precomposed) form so conflict detection against server/cache
	/// names (also NFC) succeeds for filenames that differ under NFD (e.g. Japanese ダ).
	private static func decodedEntryPath(_ entry: Entry) -> String {
		let utf8Path = entry.path(using: .utf8)
		let flaggedPath = entry.path
		let decoded: String
		if utf8Path.isEmpty, !flaggedPath.isEmpty {
			// Bytes were not valid UTF-8 — keep the flag-based (typically CP437) decode.
			decoded = flaggedPath
		} else {
			if utf8Path != flaggedPath {
				ZipDebugLogging.log("decodedEntryPath: preferring UTF-8 over flagged decode utf8=\(Log.mask(utf8Path)) flagged=\(Log.mask(flaggedPath))")
			}
			decoded = utf8Path.isEmpty ? flaggedPath : utf8Path
		}
		return decoded.precomposedStringWithCanonicalMapping
	}

	private static func sanitizedArchiveEntryPath(_ path: String) -> String? {
		let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard trimmed.isEmpty == false else {
			return nil
		}

		let components = trimmed.split(separator: "/").map { String($0).precomposedStringWithCanonicalMapping }
		guard components.count > 0, components.contains("..") == false, components.contains(where: { $0 == "." }) == false else {
			return nil
		}

		return components.joined(separator: "/")
	}

	struct ZipUploadItemEvent {
		enum Kind {
			case folder
			case file
		}
		let kind: Kind
		let localID: String
		let relativePath: String
	}

	/// Imports extracted files/folders into the vault as placeholders; sync uploads separately.
	static func importExtractedContents(
		at localDirectory: URL,
		to parentItem: OCItem,
		core: OCCore,
		skipRelativePaths: Set<String> = [],
		publishProgress: @escaping (Progress) -> Void,
		onProgressCreated: ((Progress) -> Void)? = nil,
		onItemCreated: ((ZipUploadItemEvent) -> Void)? = nil,
		completion: @escaping (Error?) -> Void
	) {
		let profile = ZipDebugLogging.ProfileScope(
			"importExtractedContents",
			extra: "parent=\(Log.mask(parentItem.name ?? "nil"))"
		)

		ZipDebugLogging.log(url: localDirectory, context: "importExtractedContents.localDirectory")
		ZipDebugLogging.log(item: parentItem, context: "importExtractedContents.parentItem")

		let fileEntries = collectLocalFileEntries(at: localDirectory).filter { !skipRelativePaths.contains($0.archiveRelativePath) }
		var directoryPaths = directoryPaths(for: fileEntries)
		directoryPaths.append(contentsOf: collectEmptyDirectoryPaths(at: localDirectory))
		directoryPaths = Array(Set(directoryPaths)).sorted { lhs, rhs in
			lhs.split(separator: "/").count < rhs.split(separator: "/").count
		}
		directoryPaths = directoryPaths.filter { !skipRelativePaths.contains($0) }

		profile.mark(
			"enumerateLocal",
			extra: "files=\(fileEntries.count) dirs=\(directoryPaths.count) skipped=\(skipRelativePaths.count)"
		)

		ZipDebugLogging.log("importExtractedContents: found \(fileEntries.count) file(s), \(directoryPaths.count) director\(directoryPaths.count == 1 ? "y" : "ies") to create")
		for (index, entry) in fileEntries.enumerated() {
			ZipDebugLogging.log("importExtractedContents.file[\(index)]: relativePath=\(Log.mask(entry.archiveRelativePath)) localURL=\(Log.mask(entry.localURL.path))")
		}
		for (index, directoryPath) in directoryPaths.enumerated() {
			ZipDebugLogging.log("importExtractedContents.directory[\(index)]: path=\(Log.mask(directoryPath))")
		}

		guard fileEntries.count > 0 || directoryPaths.count > 0 else {
			ZipDebugLogging.log("importExtractedContents: aborting — extract directory has no files or folders")
			profile.end(extra: "aborted=empty")
			completion(NSError(ocError: .internal))
			return
		}

		let overallUploadProgress = Progress(totalUnitCount: Int64(max(fileEntries.count + directoryPaths.count, 1)))
		publishProgress(overallUploadProgress)

		var createdFolderPaths = Set<String>()
		let folderMapStart = CFAbsoluteTimeGetCurrent()

		// Cover folder + file placeholders in one bulk section so the destination
		// folder is not published until every child placeholder is ready.
		core.beginBulkLocalMutations()
		final class EndBulkOnce {
			private let core: OCCore
			private let lock = NSLock()
			private var didEnd = false

			init(_ core: OCCore) {
				self.core = core
			}

			func end() {
				lock.lock()
				defer { lock.unlock() }
				guard !didEnd else { return }
				didEnd = true
				core.endBulkLocalMutations()
			}
		}
		let endBulkOnce = EndBulkOnce(core)

		buildFolderMap(
			directoryPaths: directoryPaths,
			parentItem: parentItem,
			core: core,
			cancelProgress: overallUploadProgress,
			onProgressCreated: onProgressCreated,
			onFolderCreated: { localID, relativePath in
				createdFolderPaths.insert(relativePath)
				onItemCreated?(ZipUploadItemEvent(kind: .folder, localID: localID, relativePath: relativePath))
				overallUploadProgress.completedUnitCount = min(overallUploadProgress.totalUnitCount, overallUploadProgress.completedUnitCount + 1)
			}
		) { result in
			let folderMapMs = (CFAbsoluteTimeGetCurrent() - folderMapStart) * 1000
			if overallUploadProgress.isCancelled {
				endBulkOnce.end()
				profile.end(extra: "cancelled=folderMap")
				completion(NSError(ocError: .cancelled))
				return
			}
			switch result {
			case .failure(let error):
				endBulkOnce.end()
				ZipDebugLogging.log(error: error, context: "importExtractedContents.buildFolderMap")
				profile.end(extra: "failed=folderMap")
				completion(error)
			case .success(let folderItems):
				profile.mark(
					"buildFolderMap",
					extra: "elapsed=\(String(format: "%.0f", folderMapMs))ms folders=\(folderItems.count) newlyCreated=\(createdFolderPaths.count)"
				)
				ZipDebugLogging.log("importExtractedContents: folder map ready with \(folderItems.count) item(s), \(createdFolderPaths.count) newly created")
				uploadFileEntries(
					fileEntries,
					folderItems: folderItems,
					newlyCreatedFolderPaths: createdFolderPaths,
					core: core,
					overallUploadProgress: overallUploadProgress,
					onProgressCreated: onProgressCreated,
					onFileCreated: { localID, relativePath in
						onItemCreated?(ZipUploadItemEvent(kind: .file, localID: localID, relativePath: relativePath))
					},
					completion: { error in
						// Flush coalesced query updates (folder + all files) before the job
						// reports success, so opening the folder shows the full list at once.
						endBulkOnce.end()
						if let error {
							profile.end(extra: "failed=uploadFileEntries")
						} else {
							profile.end(extra: "files=\(fileEntries.count) folders=\(createdFolderPaths.count)")
						}
						completion(error)
					}
				)
			}
		}
	}

	private static func buildFolderMap(
		directoryPaths: [String],
		parentItem: OCItem,
		core: OCCore,
		cancelProgress: Progress,
		onProgressCreated: ((Progress) -> Void)?,
		onFolderCreated: ((String, String) -> Void)?,
		completion: @escaping (Result<[String: OCItem], Error>) -> Void
	) {
		let profile = ZipDebugLogging.ProfileScope(
			"buildFolderMap",
			extra: "dirs=\(directoryPaths.count)"
		)
		var folderItems: [String: OCItem] = ["": parentItem]
		/// Relative paths created in this map (not the pre-existing destination parent).
		var newlyCreatedPaths = Set<String>()
		var conflictChecks = 0
		var skippedConflictChecks = 0

		func createFolder(named folderName: String, inside parentFolderItem: OCItem, directoryPath: String, nextIndex: Int) {
			let folderStart = CFAbsoluteTimeGetCurrent()
			ZipDebugLogging.log("buildFolderMap: creating folder name=\(Log.mask(folderName)) path=\(Log.mask(directoryPath))")

			// Use placeholderCompletionHandler so the placeholder OCItem (which is live in
			// the local database) is available immediately for child imports. resultHandler
			// only fires after the server round-trip and returns a snapshot that may not
			// match the current DB entry — passing that snapshot to importFileNamed can
			// cause the import to fail silently.
			let createProgress = core.createFolder(folderName, inside: parentFolderItem, options: nil, placeholderCompletionHandler: { error, folderItem in
				let createMs = (CFAbsoluteTimeGetCurrent() - folderStart) * 1000
				if cancelProgress.isCancelled {
					profile.end(extra: "cancelled")
					completion(.failure(NSError(ocError: .cancelled)))
					return
				}
				if let error = error {
					ZipDebugLogging.log(error: error, context: "buildFolderMap.createFolder(\(Log.mask(directoryPath)))")
					profile.end(extra: "failed")
					completion(.failure(error))
					return
				}

				guard let folderItem = folderItem else {
					ZipDebugLogging.log("buildFolderMap: createFolder placeholder nil for path=\(Log.mask(directoryPath))")
					profile.end(extra: "failed=nilPlaceholder")
					completion(.failure(NSError(ocError: .internal)))
					return
				}

				ZipDebugLogging.log("buildFolderMap: placeholder ready localID=\(Log.mask(folderItem.localID ?? "nil")) path=\(Log.mask(directoryPath))")
				folderItems[directoryPath] = folderItem
				newlyCreatedPaths.insert(directoryPath)
				if let localID = folderItem.localID as String? {
					onFolderCreated?(localID, directoryPath)
				}
				if nextIndex == directoryPaths.count || nextIndex % 10 == 0 {
					ZipDebugLogging.log(
						"⏱ PROFILE mark buildFolderMap.progress \(nextIndex)/\(directoryPaths.count) lastCreate=\(String(format: "%.0f", createMs))ms"
					)
				}
				createNext(startingAt: nextIndex)
			}, resultHandler: { error, _, _, _ in
				if let error = error {
					ZipDebugLogging.log(error: error, context: "buildFolderMap.createFolder.server(\(Log.mask(directoryPath)))")
				} else {
					ZipDebugLogging.log("buildFolderMap: server confirmed folder path=\(Log.mask(directoryPath))")
				}
			})
			if let createProgress {
				onProgressCreated?(createProgress)
			}
		}

		func createNext(startingAt index: Int) {
			if cancelProgress.isCancelled {
				profile.end(extra: "cancelled")
				completion(.failure(NSError(ocError: .cancelled)))
				return
			}

			if index >= directoryPaths.count {
				ZipDebugLogging.log("buildFolderMap: created \(folderItems.count - 1) folder(s)")
				profile.end(
					extra: "created=\(newlyCreatedPaths.count) conflictChecks=\(conflictChecks) skippedConflict=\(skippedConflictChecks)"
				)
				completion(.success(folderItems))
				return
			}

			let directoryPath = directoryPaths[index]
			let parentPath = (directoryPath as NSString).deletingLastPathComponent
			let folderName = (directoryPath as NSString).lastPathComponent

			guard let parentFolderItem = folderItems[parentPath], let parentLocation = parentFolderItem.location else {
				ZipDebugLogging.log("buildFolderMap: missing parent for path=\(Log.mask(directoryPath)) parentPath=\(Log.mask(parentPath))")
				profile.end(extra: "failed=missingParent")
				completion(.failure(NSError(ocError: .itemNotFound)))
				return
			}

			// Parent just created in this import is empty — skip suggestUnusedName (blocking
			// OCSyncExec). Still resolve conflicts when creating into the existing destination.
			if newlyCreatedPaths.contains(parentPath) {
				skippedConflictChecks += 1
				createFolder(named: folderName, inside: parentFolderItem, directoryPath: directoryPath, nextIndex: index + 1)
				return
			}

			conflictChecks += 1
			let suggestStart = CFAbsoluteTimeGetCurrent()
			core.suggestUnusedNameBased(on: folderName, at: parentLocation, isDirectory: true, using: .bracketed, filteredBy: nil, resultHandler: { suggestedName, _ in
				let suggestMs = (CFAbsoluteTimeGetCurrent() - suggestStart) * 1000
				ZipDebugLogging.log(
					"⏱ PROFILE mark buildFolderMap.suggestUnusedName +\(String(format: "%.0f", suggestMs))ms name=\(Log.mask(folderName))"
				)
				if cancelProgress.isCancelled {
					profile.end(extra: "cancelled")
					completion(.failure(NSError(ocError: .cancelled)))
					return
				}

				guard let suggestedName = suggestedName else {
					ZipDebugLogging.log("buildFolderMap: no suggested name for folder=\(Log.mask(folderName)) at path=\(Log.mask(directoryPath))")
					profile.end(extra: "failed=noSuggestedName")
					completion(.failure(NSError(ocError: .internal)))
					return
				}

				createFolder(named: suggestedName, inside: parentFolderItem, directoryPath: directoryPath, nextIndex: index + 1)
			})
		}

		createNext(startingAt: 0)
	}

	private static func uploadFileEntries(
		_ fileEntries: [ZipLocalEntry],
		folderItems: [String: OCItem],
		newlyCreatedFolderPaths: Set<String>,
		core: OCCore,
		overallUploadProgress: Progress,
		onProgressCreated: ((Progress) -> Void)?,
		onFileCreated: ((String, String) -> Void)?,
		completion: @escaping (Error?) -> Void
	) {
		guard fileEntries.count > 0 else {
			ZipDebugLogging.log("uploadFileEntries: no files to import — done")
			completion(nil)
			return
		}

		if overallUploadProgress.isCancelled {
			completion(NSError(ocError: .cancelled))
			return
		}

		let maxConcurrent = max(1, maxConcurrentImports)
		let profile = ZipDebugLogging.ProfileScope(
			"uploadFileEntries",
			extra: "files=\(fileEntries.count) maxConcurrent=\(maxConcurrent)"
		)

		ZipDebugLogging.log("uploadFileEntries: importing \(fileEntries.count) file(s); maxConcurrentImports=\(maxConcurrent)")

		struct PendingImport {
			let entry: ZipLocalEntry
			let parentFolderItem: OCItem
			let parentPath: String
			let fileName: String
			let importOptions: [OCCoreOption: Any]
		}

		/// `importFileNamed` can both invoke `placeholderCompletionHandler` and return `nil`
		/// (criticalError path). Guard so we never leave more times than we enter.
		final class LeaveOnce {
			private let group: DispatchGroup
			private let lock = NSLock()
			private var didLeave = false

			init(_ group: DispatchGroup) {
				self.group = group
			}

			@discardableResult
			func leave() -> Bool {
				lock.lock()
				defer { lock.unlock() }
				guard !didLeave else { return false }
				didLeave = true
				group.leave()
				return true
			}
		}

		// importByCopying is intentionally omitted (defaults to move). With a move OCCore
		// atomically places the file in its vault before firing placeholderCompletionHandler,
		// so the temp extract directory can be safely deleted once the group notifies.
		// Using placeholderCompletionHandler (not resultHandler) means we complete as soon
		// as all files are queued in the sync engine — actual server uploads are handled
		// through the normal app sync pipeline.
		let conflictOptions: [OCCoreOption: Any] = [
			.automaticConflictResolutionNameStyle: OCCoreDuplicateNameStyle.bracketed.rawValue
		]

		let uploadGroup = DispatchGroup()
		var firstError: Error?
		let stateLock = NSLock()
		var conflictChecks = 0
		var skippedConflictChecks = 0
		var completedPlaceholders = 0
		var importCallMsTotal: Double = 0
		var pending: [PendingImport] = []
		pending.reserveCapacity(fileEntries.count)
		var activeCount = 0
		var didFinishPumping = false

		for entry in fileEntries {
			let parentPath = (entry.archiveRelativePath as NSString).deletingLastPathComponent
			guard let parentFolderItem = folderItems[parentPath] ?? folderItems[""] else {
				ZipDebugLogging.log("uploadFileEntries: missing parent folder for relativePath=\(Log.mask(entry.archiveRelativePath)) parentPath=\(Log.mask(parentPath))")
				stateLock.lock()
				if firstError == nil { firstError = NSError(ocError: .itemNotFound) }
				stateLock.unlock()
				overallUploadProgress.completedUnitCount = min(overallUploadProgress.totalUnitCount, overallUploadProgress.completedUnitCount + 1)
				continue
			}

			// Folders created in this import are empty — skip per-file suggestUnusedName
			// (blocking OCSyncExec against a busy parent). Still resolve conflicts when
			// importing into the existing destination parent (parentPath == "").
			let skipConflict = newlyCreatedFolderPaths.contains(parentPath)
			if skipConflict {
				skippedConflictChecks += 1
			} else {
				conflictChecks += 1
			}

			pending.append(PendingImport(
				entry: entry,
				parentFolderItem: parentFolderItem,
				parentPath: parentPath,
				fileName: (entry.archiveRelativePath as NSString).lastPathComponent,
				importOptions: skipConflict ? [:] : conflictOptions
			))
		}

		guard !pending.isEmpty else {
			profile.end(extra: "noValidEntries")
			completion(firstError)
			return
		}

		// Bulk local mutations are owned by importExtractedContents (covers folder map + files).

		for _ in pending {
			uploadGroup.enter()
		}

		func finishSlotAndPump(leaveOnce: LeaveOnce) {
			leaveOnce.leave()
			stateLock.lock()
			activeCount = max(0, activeCount - 1)
			stateLock.unlock()
			pumpImports()
		}

		func startImport(_ pendingImport: PendingImport) {
			let entry = pendingImport.entry
			let fileName = pendingImport.fileName
			let importOptions = pendingImport.importOptions
			let leaveOnce = LeaveOnce(uploadGroup)

			if overallUploadProgress.isCancelled {
				stateLock.lock()
				if firstError == nil { firstError = NSError(ocError: .cancelled) }
				stateLock.unlock()
				overallUploadProgress.completedUnitCount = min(overallUploadProgress.totalUnitCount, overallUploadProgress.completedUnitCount + 1)
				finishSlotAndPump(leaveOnce: leaveOnce)
				return
			}

			ZipDebugLogging.log("uploadFileEntries: queuing fileName=\(Log.mask(fileName)) parentPath=\(Log.mask(pendingImport.parentPath)) parentLocalID=\(Log.mask(pendingImport.parentFolderItem.localID ?? "nil")) from=\(Log.mask(entry.localURL.path)) conflictCheck=\(importOptions.isEmpty ? "skip" : "bracketed")")

			let callStart = CFAbsoluteTimeGetCurrent()
			// placeholderCompletionHandler fires after the file is moved into OCCore vault
			// and the placeholder is created in the local database — or immediately on criticalError
			// (in which case importFileNamed also returns nil).
			if let importProgress = core.importFileNamed(
				fileName,
				at: pendingImport.parentFolderItem,
				from: entry.localURL,
				isSecurityScoped: false,
				options: importOptions,
				placeholderCompletionHandler: { error, item in
					let callMs = (CFAbsoluteTimeGetCurrent() - callStart) * 1000
					stateLock.lock()
					importCallMsTotal += callMs
					completedPlaceholders += 1
					let done = completedPlaceholders
					let totalMs = importCallMsTotal
					stateLock.unlock()

					if done == 1 || done == fileEntries.count || done % 25 == 0 || callMs >= 500 {
						ZipDebugLogging.log(
							"⏱ PROFILE mark uploadFileEntries.placeholder \(done)/\(fileEntries.count) last=\(String(format: "%.0f", callMs))ms avg=\(String(format: "%.0f", totalMs / Double(done)))ms conflict=\(importOptions.isEmpty ? "skip" : "bracketed")"
						)
					}

					if let error = error {
						ZipDebugLogging.log(error: error, context: "uploadFileEntries.placeholder(\(Log.mask(fileName)))")
						stateLock.lock()
						if firstError == nil { firstError = error }
						stateLock.unlock()
					} else {
						ZipDebugLogging.log("uploadFileEntries: queued \(Log.mask(fileName)) localID=\(Log.mask(item?.localID ?? "nil"))")
						if let localID = item?.localID as String? {
							onFileCreated?(localID, entry.archiveRelativePath)
						}
					}
					overallUploadProgress.completedUnitCount = min(overallUploadProgress.totalUnitCount, overallUploadProgress.completedUnitCount + 1)
					finishSlotAndPump(leaveOnce: leaveOnce)
				},
				resultHandler: { error, _, _, _ in
					if let error = error {
						ZipDebugLogging.log(error: error, context: "uploadFileEntries.serverUpload(\(Log.mask(fileName)))")
					} else {
						ZipDebugLogging.log("uploadFileEntries: server upload done \(Log.mask(fileName))")
					}
				}
			) {
				onProgressCreated?(importProgress)
				ZipDebugLogging.log("uploadFileEntries: import progress started for \(Log.mask(fileName))")
			} else {
				ZipDebugLogging.log("uploadFileEntries: importFileNamed returned nil for \(Log.mask(fileName))")
				// If placeholderCompletionHandler already ran (criticalError path), leave/progress
				// were handled there — only bookkeep when we are the ones leaving.
				if leaveOnce.leave() {
					stateLock.lock()
					if firstError == nil { firstError = NSError(ocError: .internal) }
					activeCount = max(0, activeCount - 1)
					stateLock.unlock()
					overallUploadProgress.completedUnitCount = min(overallUploadProgress.totalUnitCount, overallUploadProgress.completedUnitCount + 1)
					pumpImports()
				}
			}
		}

		func pumpImports() {
			var toStart: [PendingImport] = []
			stateLock.lock()
			while activeCount < maxConcurrent, !pending.isEmpty, !overallUploadProgress.isCancelled {
				toStart.append(pending.removeFirst())
				activeCount += 1
			}
			let remaining = pending.count
			let active = activeCount
			let shouldMarkDispatchDone = pending.isEmpty && !didFinishPumping
			if shouldMarkDispatchDone {
				didFinishPumping = true
			}
			stateLock.unlock()

			if !toStart.isEmpty {
				ZipDebugLogging.log("uploadFileEntries: starting \(toStart.count) import(s); active=\(active) queued=\(remaining) max=\(maxConcurrent)")
			}

			if shouldMarkDispatchDone {
				profile.mark(
					"dispatchImports",
					extra: "conflictChecks=\(conflictChecks) skippedConflict=\(skippedConflictChecks)"
				)
				ZipDebugLogging.log("uploadFileEntries: all \(fileEntries.count) import(s) scheduled — waiting for placeholders")
			}

			// Async starts avoid deep recursion if importFileNamed completes synchronously.
			for item in toStart {
				DispatchQueue.global(qos: .userInitiated).async {
					startImport(item)
				}
			}

			if overallUploadProgress.isCancelled {
				stateLock.lock()
				let leftovers = pending
				pending.removeAll()
				if firstError == nil { firstError = NSError(ocError: .cancelled) }
				stateLock.unlock()
				for _ in leftovers {
					overallUploadProgress.completedUnitCount = min(overallUploadProgress.totalUnitCount, overallUploadProgress.completedUnitCount + 1)
					uploadGroup.leave()
				}
			}
		}

		pumpImports()

		uploadGroup.notify(queue: .main) {
			if overallUploadProgress.isCancelled {
				profile.end(extra: "cancelled")
				completion(NSError(ocError: .cancelled))
				return
			}
			overallUploadProgress.completedUnitCount = overallUploadProgress.totalUnitCount
			stateLock.lock()
			let avgMs = completedPlaceholders > 0 ? importCallMsTotal / Double(completedPlaceholders) : 0
			let placeholders = completedPlaceholders
			let error = firstError
			stateLock.unlock()
			if let error {
				ZipDebugLogging.log(error: error, context: "uploadFileEntries.allQueued")
				profile.end(extra: "failed placeholders=\(placeholders)")
			} else {
				ZipDebugLogging.log("uploadFileEntries: all placeholders created — sync engine will handle uploads")
				profile.end(
					extra: "placeholders=\(placeholders) avgImport=\(String(format: "%.0f", avgMs))ms conflictChecks=\(conflictChecks) skippedConflict=\(skippedConflictChecks) maxConcurrent=\(maxConcurrent)"
				)
			}
			completion(error)
		}
	}

	private static func archiveRelativePath(for item: OCItem, under rootItem: OCItem) -> String? {
		guard let rootName = rootItem.name else {
			return item.name
		}

		if item.localID == rootItem.localID {
			return rootName
		}

		if let itemPath = item.path, let rootPath = rootItem.path {
			let normalizedItemPath = normalizedPath(itemPath)
			let normalizedRootPath = normalizedPath(rootPath)

			if normalizedItemPath == normalizedRootPath {
				return rootName
			}

			if normalizedItemPath.hasPrefix(normalizedRootPath + "/") {
				let suffix = String(normalizedItemPath.dropFirst(normalizedRootPath.count + 1))
				if suffix.isEmpty {
					return rootName
				}
				return "\(rootName)/\(suffix)"
			}
		}

		if let parentPath = item.parentPath, let rootPath = rootItem.path, normalizedPath(parentPath) == normalizedPath(rootPath), let name = item.name {
			return "\(rootName)/\(name)"
		}

		return item.name
	}

	private static func isChild(_ child: OCItem, of folderItem: OCItem) -> Bool {
		if child.localID == folderItem.localID {
			return false
		}

		if child.parentLocalID != nil, child.parentLocalID == folderItem.localID {
			return true
		}

		guard let childPath = child.path, let folderPath = folderItem.path else {
			return false
		}

		let normalizedChildPath = normalizedPath(childPath)
		let normalizedFolderPath = normalizedPath(folderPath)

		if normalizedChildPath == normalizedFolderPath {
			return false
		}

		return normalizedChildPath.hasPrefix(normalizedFolderPath + "/")
	}

	private static func normalizedPath(_ path: String) -> String {
		if path == "/" {
			return path
		}

		return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
	}

	private static func collectEmptyDirectoryPaths(at directory: URL) -> [String] {
		let fileManager = FileManager.default
		guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
			ZipDebugLogging.log("collectEmptyDirectoryPaths: failed to enumerate \(Log.mask(directory.path))")
			return []
		}

		var paths: [String] = []

		for case let itemURL as URL in enumerator {
			guard let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else {
				continue
			}

			let relativePath = relativePath(from: directory, to: itemURL)
			guard relativePath.isEmpty == false else { continue }

			paths.append(relativePath)
		}

		return paths
	}

	private static func collectLocalFileEntries(at directory: URL) -> [ZipLocalEntry] {
		let fileManager = FileManager.default
		guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
			ZipDebugLogging.log("collectLocalFileEntries: failed to enumerate \(Log.mask(directory.path))")
			return []
		}

		var entries: [ZipLocalEntry] = []

		for case let itemURL as URL in enumerator {
			guard let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory != true else {
				continue
			}

			let relativePath = relativePath(from: directory, to: itemURL)
			guard relativePath.isEmpty == false else { continue }

			entries.append(ZipLocalEntry(archiveRelativePath: relativePath, localURL: itemURL))
		}

		return entries.sorted { $0.archiveRelativePath < $1.archiveRelativePath }
	}

	private static func directoryPaths(for fileEntries: [ZipLocalEntry]) -> [String] {
		var paths = Set<String>()

		for entry in fileEntries {
			var parentPath = (entry.archiveRelativePath as NSString).deletingLastPathComponent
			while parentPath.isEmpty == false {
				paths.insert(parentPath)
				parentPath = (parentPath as NSString).deletingLastPathComponent
			}
		}

		return paths.sorted { lhs, rhs in
			lhs.split(separator: "/").count < rhs.split(separator: "/").count
		}
	}

	private static func relativePath(from rootURL: URL, to itemURL: URL) -> String {
		let rootPath = rootURL.standardizedFileURL.path
		let itemPath = itemURL.standardizedFileURL.path

		guard itemPath.hasPrefix(rootPath) else { return "" }

		return String(itemPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
	}
}

extension ZipDebugLogging {
	static func log(plan: ZipArchivePlan, context: String) {
		guard isVerbose else { return }
		log("\(context): \(plan.fileEntries.count) file entr\(plan.fileEntries.count == 1 ? "y" : "ies"), \(plan.emptyFolderPaths.count) empty folder path(s), \(plan.folderItems.count) folder(s)")
		for (index, entry) in plan.fileEntries.enumerated() {
			log(item: entry.item, context: "\(context).fileEntry[\(index)].item")
			log("\(context).fileEntry[\(index)]: archiveRelativePath=\(Log.mask(entry.archiveRelativePath))")
		}
		for (index, path) in plan.emptyFolderPaths.enumerated() {
			log("\(context).emptyFolder[\(index)]: path=\(Log.mask(path))")
		}
		for (index, folder) in plan.folderItems.enumerated() {
			log(item: folder, context: "\(context).folder[\(index)]")
		}
	}

	static func log(localEntries: [ZipLocalEntry], context: String) {
		guard isVerbose else { return }
		log("\(context): \(localEntries.count) local entr\(localEntries.count == 1 ? "y" : "ies")")
		for (index, entry) in localEntries.enumerated() {
			log("\(context)[\(index)]: relativePath=\(Log.mask(entry.archiveRelativePath)) localURL=\(Log.mask(entry.localURL.path))")
		}
	}
}
