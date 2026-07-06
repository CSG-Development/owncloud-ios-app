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
}

enum ZipArchiveService {
	static func suggestedArchiveName(for items: [OCItem]) -> String {
		guard items.count == 1, let item = items.first, let name = item.name else {
			return HCL10n.ZipAction.defaultArchiveName
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

		// Enumerate folder contents and download each file individually in
		// downloadArchiveEntries. makeAvailableOffline is intentionally not used
		// here — it can leave files stuck in .downloading (especially when the
		// folder tree contains empty subfolders) and blocks compress progress.
		collectArchivePlanEntries(for: items, core: core, completion: completion)
	}

	private static func collectArchivePlanEntries(for items: [OCItem], core: OCCore, completion: @escaping (Result<ZipArchivePlan, Error>) -> Void) {
		var fileEntries: [ZipArchiveEntry] = []
		var emptyFolderPaths: [String] = []
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
					ZipDebugLogging.log("collectArchivePlanEntries: folder \(Log.mask(item.name ?? "nil")) contributed \(contents.fileEntries.count) file(s), \(contents.emptyFolderPaths.count) empty folder path(s)")
					fileEntries.append(contentsOf: contents.fileEntries)
					emptyFolderPaths.append(contentsOf: contents.emptyFolderPaths)
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

			let plan = ZipArchivePlan(fileEntries: downloadableFileEntries, emptyFolderPaths: emptyFolderPaths)
			ZipDebugLogging.log(plan: plan, context: "collectArchivePlanEntries")
			completion(.success(plan))
		}
	}

	static func downloadArchiveEntries(_ plan: ZipArchivePlan, core: OCCore, completion: @escaping (Result<[ZipLocalEntry], Error>) -> Void) {
		ZipDebugLogging.log(plan: plan, context: "downloadArchiveEntries")
		guard plan.fileEntries.count > 0 else {
			ZipDebugLogging.log("downloadArchiveEntries: no files in plan — returning empty result")
			completion(.success([]))
			return
		}

		let deadline = Date().addingTimeInterval(600)
		var inFlightDownloadKeys = Set<String>()
		var lastLoggedDownloadedCount = -1

		func itemKey(for item: OCItem, fallback: String) -> String {
			item.localID ?? item.path ?? fallback
		}

		func poll() {
			var localEntries: [ZipLocalEntry] = []
			var missingEntries: [ZipArchiveEntry] = []

			for entry in plan.fileEntries {
				let item = resolvedItem(entry.item, core: core)
				guard item.type == .file else {
					ZipDebugLogging.log("downloadArchiveEntries: skipping non-file entry \(Log.mask(entry.archiveRelativePath)) type=\(item.type.rawValue)")
					continue
				}
				if let localURL = localFileURL(for: item, core: core) {
					core.registerUsage(of: item, completionHandler: nil)
					localEntries.append(ZipLocalEntry(archiveRelativePath: entry.archiveRelativePath, localURL: localURL))
				} else {
					missingEntries.append(entry)
				}
			}

			if localEntries.count != lastLoggedDownloadedCount {
				lastLoggedDownloadedCount = localEntries.count
				ZipDebugLogging.log("downloadArchiveEntries: progress \(localEntries.count)/\(plan.fileEntries.count) ready, \(missingEntries.count) missing")
			}

			if missingEntries.isEmpty {
				ZipDebugLogging.log(localEntries: localEntries, context: "downloadArchiveEntries.completed")
				completion(.success(localEntries))
				return
			}

			if Date() > deadline {
				ZipDebugLogging.log("downloadArchiveEntries: timed out with \(missingEntries.count) file(s) still missing")
				for entry in missingEntries {
					let item = resolvedItem(entry.item, core: core)
					ZipDebugLogging.log("downloadArchiveEntries.missing: relativePath=\(Log.mask(entry.archiveRelativePath)) path=\(Log.mask(item.path ?? "nil")) syncActivity=\(item.syncActivity.rawValue) localRelativePath=\(Log.mask(item.localRelativePath ?? "nil"))")
				}
				completion(.failure(NSError(ocError: .requestTimeout)))
				return
			}

			for entry in missingEntries {
				let item = resolvedItem(entry.item, core: core)
				guard item.type == .file else {
					continue
				}
				let key = itemKey(for: item, fallback: entry.archiveRelativePath)

				if inFlightDownloadKeys.contains(key) {
					continue
				}

				inFlightDownloadKeys.insert(key)
				ZipDebugLogging.log("downloadArchiveEntries: starting download for \(Log.mask(entry.archiveRelativePath)) path=\(Log.mask(item.path ?? "nil")) localRelativePath=\(Log.mask(item.localRelativePath ?? "nil"))")
				_ = core.downloadItem(item, options: [
					.returnImmediatelyIfOfflineOrUnavailable: true,
					.addTemporaryClaimForPurpose: OCCoreClaimPurpose.view.rawValue
				], resultHandler: { error, _, _, _ in
					inFlightDownloadKeys.remove(key)
					if let error = error {
						ZipDebugLogging.log(error: error, context: "downloadArchiveEntries.download(\(Log.mask(entry.archiveRelativePath)))")
					} else {
						ZipDebugLogging.log("downloadArchiveEntries: download finished for \(Log.mask(entry.archiveRelativePath))")
					}
				})
			}

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				poll()
			}
		}

		ZipDebugLogging.log("downloadArchiveEntries: polling for local copies (timeout 600s)")
		poll()
	}

	static func resolvedItemForDownload(_ item: OCItem, core: OCCore) -> OCItem {
		resolvedItem(item, core: core)
	}

	static func localFileURL(for item: OCItem, core: OCCore) -> URL? {
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
	}

	private static func collectFolderContents(folderItem: OCItem, rootItem: OCItem, core: OCCore, completion: @escaping (Result<FolderContents, Error>) -> Void) {
		guard let location = folderItem.location else {
			ZipDebugLogging.log("collectFolderContents: folder has no location name=\(Log.mask(folderItem.name ?? "nil"))")
			completion(.failure(NSError(ocError: .itemNotFound)))
			return
		}

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
					completion(.success(FolderContents(fileEntries: [], emptyFolderPaths: [relativePath])))
				} else {
					ZipDebugLogging.log("collectFolderContents: no children and no relative path for \(Log.mask(folderItem.name ?? "nil"))")
					completion(.success(FolderContents(fileEntries: [], emptyFolderPaths: [])))
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
			collectSubfolderContents(subfolders, startingAt: 0, rootItem: rootItem, core: core, accumulatedFiles: fileEntries, accumulatedEmptyFolders: []) { result in
				completion(result)
			}
		}
	}

	private static func collectSubfolderContents(_ subfolders: [OCItem], startingAt index: Int, rootItem: OCItem, core: OCCore, accumulatedFiles: [ZipArchiveEntry], accumulatedEmptyFolders: [String], completion: @escaping (Result<FolderContents, Error>) -> Void) {
		if index >= subfolders.count {
			completion(.success(FolderContents(fileEntries: accumulatedFiles, emptyFolderPaths: accumulatedEmptyFolders)))
			return
		}

		let subfolder = subfolders[index]
		collectFolderContents(folderItem: subfolder, rootItem: rootItem, core: core) { result in
			switch result {
			case .failure(let error):
				completion(.failure(error))
			case .success(let contents):
				collectSubfolderContents(
					subfolders,
					startingAt: index + 1,
					rootItem: rootItem,
					core: core,
					accumulatedFiles: accumulatedFiles + contents.fileEntries,
					accumulatedEmptyFolders: accumulatedEmptyFolders + contents.emptyFolderPaths,
					completion: completion
				)
			}
		}
	}

	static func downloadWeight(for entries: [ZipArchiveEntry]) -> Int64 {
		let totalSize = entries.reduce(Int64(0)) { partialResult, entry in
			partialResult + max(Int64(entry.item.size), 1)
		}
		return max(totalSize, 1)
	}

	static func stageArchive(plan: ZipArchivePlan, localEntries: [ZipLocalEntry], at stagingURL: URL, progress: Progress) throws {
		ZipDebugLogging.log(plan: plan, context: "stageArchive")
		ZipDebugLogging.log(localEntries: localEntries, context: "stageArchive")
		ZipDebugLogging.log(url: stagingURL, context: "stageArchive.stagingURL(before)")

		let fileManager = FileManager.default
		try? fileManager.removeItem(at: stagingURL)
		try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true, attributes: [
			.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
		])

		let operations = localEntries.count + plan.emptyFolderPaths.count
		progress.totalUnitCount = max(Int64(operations + 1), 1)
		progress.completedUnitCount = 0
		ZipDebugLogging.log("stageArchive: staging \(localEntries.count) file(s) and \(plan.emptyFolderPaths.count) empty folder(s)")

		for emptyFolderPath in plan.emptyFolderPaths {
			let destinationURL = stagingURL.appendingPathComponent(emptyFolderPath, isDirectory: true)
			try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: [
				.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
			])
			ZipDebugLogging.log("stageArchive: created empty folder \(Log.mask(emptyFolderPath))")
			progress.completedUnitCount += 1
		}

		for entry in localEntries {
			let destinationURL = stagingURL.appendingPathComponent(entry.archiveRelativePath, isDirectory: false)
			try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [
				.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
			])

			if fileManager.fileExists(atPath: destinationURL.path) {
				try fileManager.removeItem(at: destinationURL)
			}

			ZipDebugLogging.log("stageArchive: copying \(Log.mask(entry.archiveRelativePath)) from \(Log.mask(entry.localURL.path))")
			try fileManager.copyItem(at: entry.localURL, to: destinationURL)
			progress.completedUnitCount += 1
		}

		ZipDebugLogging.log(url: stagingURL, context: "stageArchive.stagingURL(after)")
	}

	static func createArchive(at archiveURL: URL, fromStagingDirectory stagingURL: URL, progress: Progress) throws {
		ZipDebugLogging.log(url: stagingURL, context: "createArchive.stagingURL")
		ZipDebugLogging.log(url: archiveURL, context: "createArchive.archiveURL(before)")

		let fileManager = FileManager.default
		try? fileManager.removeItem(at: archiveURL)

		progress.localizedDescription = HCL10n.ZipAction.Progress.compressing

		let zipProgress = Progress(totalUnitCount: 1, parent: progress, pendingUnitCount: 1)
		ZipDebugLogging.log("createArchive: zipping staging directory")
		try fileManager.zipItem(at: stagingURL, to: archiveURL, shouldKeepParent: false, compressionMethod: .deflate, progress: zipProgress)
		progress.completedUnitCount = progress.totalUnitCount
		ZipDebugLogging.log(url: archiveURL, context: "createArchive.archiveURL(after)")
	}

	static func extractArchive(at archiveURL: URL, to destinationURL: URL, progress: Progress) throws {
		ZipDebugLogging.log(url: archiveURL, context: "extractArchive.archiveURL")
		ZipDebugLogging.log(url: destinationURL, context: "extractArchive.destinationURL(before)")

		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: destinationURL.path) {
			ZipDebugLogging.log("extractArchive: removing existing destination at \(Log.mask(destinationURL.path))")
			try fileManager.removeItem(at: destinationURL)
		}
		try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: [
			.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
		])
		ZipDebugLogging.log(url: destinationURL, context: "extractArchive.destinationURL(afterCreate)")

		guard let archive = Archive(url: archiveURL, accessMode: .read) else {
			ZipDebugLogging.log("extractArchive: failed to open archive at \(Log.mask(archiveURL.path))")
			throw NSError(ocError: .internal)
		}

		let rawEntries = Array(archive)
		ZipDebugLogging.log("extractArchive: archive contains \(rawEntries.count) raw entr\(rawEntries.count == 1 ? "y" : "ies")")

		for (index, entry) in rawEntries.enumerated() {
			ZipDebugLogging.log("extractArchive.rawEntry[\(index)]: path=\(Log.mask(entry.path)) type=\(entry.type)")
		}

		// sanitizedArchiveEntryPath rejects any path with "..", ".", leading/trailing slashes
		// or empty components, so appending to destinationURL is always safe — no further
		// containment check is needed or reliable across iOS symlink aliases (/var vs /private/var).
		var entries = rawEntries.filter { sanitizedArchiveEntryPath($0.path) != nil }
		let skippedCount = rawEntries.count - entries.count
		if skippedCount > 0 {
			ZipDebugLogging.log("extractArchive: skipped \(skippedCount) unsafe/empty entr\(skippedCount == 1 ? "y" : "ies")")
		}

		// Directories first, then by depth so parents always exist before children
		entries.sort { lhs, rhs in
			if lhs.type != rhs.type { return lhs.type == .directory }
			return lhs.path.split(separator: "/").count < rhs.path.split(separator: "/").count
		}

		progress.localizedDescription = HCL10n.ZipAction.Progress.decompressing
		progress.totalUnitCount = max(Int64(entries.count), 1)
		progress.completedUnitCount = 0

		if entries.isEmpty {
			ZipDebugLogging.log("extractArchive: no extractable entries remain after filtering")
		}

		var extractedCount = 0
		var skippedDuringExtractCount = 0

		for (index, entry) in entries.enumerated() {
			if progress.isCancelled {
				ZipDebugLogging.log("extractArchive: cancelled at entry \(index + 1)/\(entries.count)")
				throw NSError(ocError: .cancelled)
			}

			guard let relativePath = sanitizedArchiveEntryPath(entry.path) else {
				skippedDuringExtractCount += 1
				ZipDebugLogging.log("extractArchive: skipping entry[\(index)] path=\(Log.mask(entry.path)) reason=invalidSanitizedPath")
				continue
			}

			// Build the URL one component at a time so Foundation handles encoding correctly
			let entryURL: URL = relativePath
				.split(separator: "/")
				.map(String.init)
				.reduce(destinationURL) { url, component in
					url.appendingPathComponent(component)
				}

			ZipDebugLogging.log("extractArchive: entry[\(index)] relativePath=\(Log.mask(relativePath)) type=\(entry.type) -> \(Log.mask(entryURL.path))")

			try removeItemIfExists(at: entryURL)
			do {
				_ = try archive.extract(entry, to: entryURL)
			} catch {
				ZipDebugLogging.log(error: error, context: "extractArchive.extract(\(Log.mask(relativePath)))")
				throw error
			}
			extractedCount += 1
			ZipDebugLogging.log("extractArchive: extracted[\(extractedCount)] path=\(Log.mask(relativePath))")

			progress.completedUnitCount = Int64(index + 1)
		}

		ZipDebugLogging.log("extractArchive: finished extracted=\(extractedCount) skippedDuringExtract=\(skippedDuringExtractCount) destination=\(Log.mask(destinationURL.path))")

		if extractedCount == 0, entries.isEmpty == false {
			ZipDebugLogging.log("extractArchive: no entries were extracted")
			throw NSError(ocError: .internal)
		}
	}

	private static func sanitizedArchiveEntryPath(_ path: String) -> String? {
		let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard trimmed.isEmpty == false else {
			return nil
		}

		let components = trimmed.split(separator: "/").map(String.init)
		guard components.count > 0, components.contains("..") == false, components.contains(where: { $0 == "." }) == false else {
			return nil
		}

		return components.joined(separator: "/")
	}

	private static func removeItemIfExists(at url: URL) throws {
		let fileManager = FileManager.default
		guard fileManager.fileExists(atPath: url.path) else {
			return
		}

		try fileManager.removeItem(at: url)
	}

	static func uploadExtractedContents(at localDirectory: URL, to parentItem: OCItem, core: OCCore, publishProgress: @escaping (Progress) -> Void, completion: @escaping (Error?) -> Void) {
		ZipDebugLogging.log(url: localDirectory, context: "uploadExtractedContents.localDirectory")
		ZipDebugLogging.log(item: parentItem, context: "uploadExtractedContents.parentItem")

		let fileEntries = collectLocalFileEntries(at: localDirectory)
		var directoryPaths = directoryPaths(for: fileEntries)
		directoryPaths.append(contentsOf: collectEmptyDirectoryPaths(at: localDirectory))
		directoryPaths = Array(Set(directoryPaths)).sorted { lhs, rhs in
			lhs.split(separator: "/").count < rhs.split(separator: "/").count
		}

		ZipDebugLogging.log("uploadExtractedContents: found \(fileEntries.count) file(s), \(directoryPaths.count) director\(directoryPaths.count == 1 ? "y" : "ies") to create")
		for (index, entry) in fileEntries.enumerated() {
			ZipDebugLogging.log("uploadExtractedContents.file[\(index)]: relativePath=\(Log.mask(entry.archiveRelativePath)) localURL=\(Log.mask(entry.localURL.path))")
		}
		for (index, directoryPath) in directoryPaths.enumerated() {
			ZipDebugLogging.log("uploadExtractedContents.directory[\(index)]: path=\(Log.mask(directoryPath))")
		}

		guard fileEntries.count > 0 || directoryPaths.count > 0 else {
			ZipDebugLogging.log("uploadExtractedContents: aborting — extract directory has no files or folders")
			completion(NSError(ocError: .internal))
			return
		}

		buildFolderMap(directoryPaths: directoryPaths, parentItem: parentItem, core: core) { result in
			switch result {
			case .failure(let error):
				ZipDebugLogging.log(error: error, context: "uploadExtractedContents.buildFolderMap")
				completion(error)
			case .success(let folderItems):
				ZipDebugLogging.log("uploadExtractedContents: folder map ready with \(folderItems.count) item(s)")
				uploadFileEntries(fileEntries, folderItems: folderItems, core: core, publishProgress: publishProgress, completion: completion)
			}
		}
	}

	private static func buildFolderMap(directoryPaths: [String], parentItem: OCItem, core: OCCore, completion: @escaping (Result<[String: OCItem], Error>) -> Void) {
		var folderItems: [String: OCItem] = ["": parentItem]

		func createNext(startingAt index: Int) {
			if index >= directoryPaths.count {
				ZipDebugLogging.log("buildFolderMap: created \(folderItems.count - 1) folder(s)")
				completion(.success(folderItems))
				return
			}

			let directoryPath = directoryPaths[index]
			let parentPath = (directoryPath as NSString).deletingLastPathComponent
			let folderName = (directoryPath as NSString).lastPathComponent

			guard let parentFolderItem = folderItems[parentPath], let parentLocation = parentFolderItem.location else {
				ZipDebugLogging.log("buildFolderMap: missing parent for path=\(Log.mask(directoryPath)) parentPath=\(Log.mask(parentPath))")
				completion(.failure(NSError(ocError: .itemNotFound)))
				return
			}

			core.suggestUnusedNameBased(on: folderName, at: parentLocation, isDirectory: true, using: .bracketed, filteredBy: nil, resultHandler: { suggestedName, _ in
				guard let suggestedName = suggestedName else {
					ZipDebugLogging.log("buildFolderMap: no suggested name for folder=\(Log.mask(folderName)) at path=\(Log.mask(directoryPath))")
					completion(.failure(NSError(ocError: .internal)))
					return
				}

			ZipDebugLogging.log("buildFolderMap: creating folder suggestedName=\(Log.mask(suggestedName)) path=\(Log.mask(directoryPath)) parentPath=\(Log.mask(parentPath))")

			// Use placeholderCompletionHandler so the placeholder OCItem (which is live in
			// the local database) is available immediately for child imports. resultHandler
			// only fires after the server round-trip and returns a snapshot that may not
			// match the current DB entry — passing that snapshot to importFileNamed can
			// cause the import to fail silently.
			_ = core.createFolder(suggestedName, inside: parentFolderItem, options: nil, placeholderCompletionHandler: { error, folderItem in
				if let error = error {
					ZipDebugLogging.log(error: error, context: "buildFolderMap.createFolder(\(Log.mask(directoryPath)))")
					completion(.failure(error))
					return
				}

				guard let folderItem = folderItem else {
					ZipDebugLogging.log("buildFolderMap: createFolder placeholder nil for path=\(Log.mask(directoryPath))")
					completion(.failure(NSError(ocError: .internal)))
					return
				}

				ZipDebugLogging.log("buildFolderMap: placeholder ready localID=\(Log.mask(folderItem.localID ?? "nil")) path=\(Log.mask(directoryPath))")
				folderItems[directoryPath] = folderItem
				createNext(startingAt: index + 1)
			}, resultHandler: { error, _, _, _ in
				if let error = error {
					ZipDebugLogging.log(error: error, context: "buildFolderMap.createFolder.server(\(Log.mask(directoryPath)))")
				} else {
					ZipDebugLogging.log("buildFolderMap: server confirmed folder path=\(Log.mask(directoryPath))")
				}
			})
			})
		}

		createNext(startingAt: 0)
	}

	private static func uploadFileEntries(_ fileEntries: [ZipLocalEntry], folderItems: [String: OCItem], core: OCCore, publishProgress: @escaping (Progress) -> Void, completion: @escaping (Error?) -> Void) {
		guard fileEntries.count > 0 else {
			ZipDebugLogging.log("uploadFileEntries: no files to import — done")
			completion(nil)
			return
		}

		ZipDebugLogging.log("uploadFileEntries: importing \(fileEntries.count) file(s)")

		let uploadGroup = DispatchGroup()
		var firstError: Error?
		let errorLock = NSLock()

		// importByCopying is intentionally omitted (defaults to move). With a move OCCore
		// atomically places the file in its vault before firing placeholderCompletionHandler,
		// so the temp extract directory can be safely deleted once the group notifies.
		// Using placeholderCompletionHandler (not resultHandler) means we complete as soon
		// as all files are queued in the sync engine — actual server uploads are handled
		// through the normal app sync pipeline.
		let importOptions: [OCCoreOption: Any] = [
			.automaticConflictResolutionNameStyle: OCCoreDuplicateNameStyle.bracketed.rawValue
		]

		for entry in fileEntries {
			let parentPath = (entry.archiveRelativePath as NSString).deletingLastPathComponent
			guard let parentFolderItem = folderItems[parentPath] ?? folderItems[""] else {
				ZipDebugLogging.log("uploadFileEntries: missing parent folder for relativePath=\(Log.mask(entry.archiveRelativePath)) parentPath=\(Log.mask(parentPath))")
				errorLock.lock()
				if firstError == nil { firstError = NSError(ocError: .itemNotFound) }
				errorLock.unlock()
				continue
			}

			let fileName = (entry.archiveRelativePath as NSString).lastPathComponent
			uploadGroup.enter()

			ZipDebugLogging.log("uploadFileEntries: queuing fileName=\(Log.mask(fileName)) parentPath=\(Log.mask(parentPath)) parentLocalID=\(Log.mask(parentFolderItem.localID ?? "nil")) from=\(Log.mask(entry.localURL.path))")

			// placeholderCompletionHandler fires after the file is moved into OCCore vault
			// and the placeholder is created in the local database.
			if core.importFileNamed(fileName, at: parentFolderItem, from: entry.localURL, isSecurityScoped: false, options: importOptions, placeholderCompletionHandler: { error, item in
				if let error = error {
					ZipDebugLogging.log(error: error, context: "uploadFileEntries.placeholder(\(Log.mask(fileName)))")
					errorLock.lock()
					if firstError == nil { firstError = error }
					errorLock.unlock()
				} else {
					ZipDebugLogging.log("uploadFileEntries: queued \(Log.mask(fileName)) localID=\(Log.mask(item?.localID ?? "nil"))")
				}
				uploadGroup.leave()
			}, resultHandler: { error, _, _, _ in
				if let error = error {
					ZipDebugLogging.log(error: error, context: "uploadFileEntries.serverUpload(\(Log.mask(fileName)))")
				} else {
					ZipDebugLogging.log("uploadFileEntries: server upload done \(Log.mask(fileName))")
				}
			}) != nil {
				ZipDebugLogging.log("uploadFileEntries: import progress started for \(Log.mask(fileName))")
			} else {
				ZipDebugLogging.log("uploadFileEntries: importFileNamed returned nil for \(Log.mask(fileName))")
				errorLock.lock()
				if firstError == nil { firstError = NSError(ocError: .internal) }
				errorLock.unlock()
				uploadGroup.leave()
			}
		}

		ZipDebugLogging.log("uploadFileEntries: all \(fileEntries.count) import(s) dispatched — waiting for placeholders")

		uploadGroup.notify(queue: .main) {
			if let firstError = firstError {
				ZipDebugLogging.log(error: firstError, context: "uploadFileEntries.allQueued")
			} else {
				ZipDebugLogging.log("uploadFileEntries: all placeholders created — sync engine will handle uploads")
			}
			completion(firstError)
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
		log("\(context): \(plan.fileEntries.count) file entr\(plan.fileEntries.count == 1 ? "y" : "ies"), \(plan.emptyFolderPaths.count) empty folder path(s)")
		for (index, entry) in plan.fileEntries.enumerated() {
			log(item: entry.item, context: "\(context).fileEntry[\(index)].item")
			log("\(context).fileEntry[\(index)]: archiveRelativePath=\(Log.mask(entry.archiveRelativePath))")
		}
		for (index, path) in plan.emptyFolderPaths.enumerated() {
			log("\(context).emptyFolder[\(index)]: path=\(Log.mask(path))")
		}
	}

	static func log(localEntries: [ZipLocalEntry], context: String) {
		log("\(context): \(localEntries.count) local entr\(localEntries.count == 1 ? "y" : "ies")")
		for (index, entry) in localEntries.enumerated() {
			log("\(context)[\(index)]: relativePath=\(Log.mask(entry.archiveRelativePath)) localURL=\(Log.mask(entry.localURL.path))")
		}
	}
}
