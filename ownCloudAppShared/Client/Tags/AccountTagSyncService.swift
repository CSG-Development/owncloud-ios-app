//
//  AccountTagSyncService.swift
//  ownCloudAppShared
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

import Foundation
import ownCloudSDK
import ownCloudApp

/// Keeps per-item local tag snapshots and a tag→fileID index in sync with the server (Android parity).
public extension Notification.Name {
	static let accountTagSyncDidFinish = Notification.Name("AccountTagSyncService.syncDidFinish")
}

public final class AccountTagSyncService {
	public static let shared = AccountTagSyncService()

	public static let bookmarkUserInfoKey = "bookmark"
	public static let defaultSyncInterval: TimeInterval = 15 * 60

	private let workQueue = DispatchQueue(label: "com.owncloud.tag-search.sync", qos: .utility)
	private var inFlightBookmarkKeys: Set<String> = []
	private let inFlightLock = NSLock()

	private let lastSyncKeyPrefix = "com.owncloud.tag-search.last-sync."
	private let cachedTagsKeyPrefix = "com.owncloud.tag-search.cached-tags."
	private let tagIndexKeyPrefix = "com.owncloud.tag-search.file-index."

	private init() {}

	// MARK: - Public API

	public func isSyncInFlight(for bookmark: OCBookmark) -> Bool {
		let bookmarkKey = bookmarkStorageKey(bookmark)
		inFlightLock.lock()
		defer { inFlightLock.unlock() }
		return inFlightBookmarkKeys.contains(bookmarkKey)
	}

	public func syncIfNeeded(for bookmark: OCBookmark, force: Bool = false, completion: (() -> Void)? = nil) {
		if !force, !shouldSync(bookmark: bookmark) {
			completion?()
			return
		}

		let bookmarkKey = bookmarkStorageKey(bookmark)
		guard beginSync(for: bookmarkKey) else {
			completion?()
			return
		}

		OCCoreManager.shared.requestCore(for: bookmark, setup: nil) { [weak self] core, error in
			guard let self, let core else {
				Log.error("No core for bookmark \(bookmark), error: \(String(describing: error))")
				self?.endSync(for: bookmarkKey)
				completion?()
				return
			}

			self.workQueue.async {
				self.performSync(core: core, bookmark: bookmark) {
					OCCoreManager.shared.returnCore(for: bookmark, completionHandler: {
						self.endSync(for: bookmarkKey)
						DispatchQueue.main.async {
							completion?()
						}
					})
				}
			}
		}
	}

	public func refreshTags(
		selection tagIDs: Set<String>,
		tagNames: Set<String> = [],
		knownTags: [OCSystemTag] = [],
		bookmark: OCBookmark,
		completion: (() -> Void)? = nil
	) {
		guard !tagIDs.isEmpty || !tagNames.isEmpty else {
			completion?()
			return
		}

		let bookmarkKey = bookmarkStorageKey(bookmark)
		workQueue.async { [weak self] in
			guard let self else {
				DispatchQueue.main.async { completion?() }
				return
			}

			guard self.beginSync(for: bookmarkKey) else {
				DispatchQueue.main.async { completion?() }
				return
			}

			OCCoreManager.shared.requestCore(for: bookmark, setup: nil) { core, error in
				guard let core else {
					self.endSync(for: bookmarkKey)
					DispatchQueue.main.async { completion?() }
					return
				}
				let connection = core.connection

				self.workQueue.async {
					defer {
						OCCoreManager.shared.returnCore(for: bookmark, completionHandler: {
							self.endSync(for: bookmarkKey)
							DispatchQueue.main.async {
								completion?()
							}
						})
					}

					var tagsToRefresh = self.resolveTagsForRefresh(
						tagIDs: tagIDs,
						tagNames: tagNames,
						knownTags: knownTags,
						bookmark: bookmark
					)

					if tagsToRefresh.isEmpty {
						let semaphore = DispatchSemaphore(value: 0)
						connection.retrieveSystemTags { error, tags in
							if error == nil {
								let visibleTags = (tags ?? []).filter(\.userVisible)
								self.saveCachedSystemTags(visibleTags, for: bookmark)
								tagsToRefresh = self.resolveTagsForRefresh(
									tagIDs: tagIDs,
									tagNames: tagNames,
									knownTags: knownTags + visibleTags,
									bookmark: bookmark
								)
							}
							semaphore.signal()
						}
						semaphore.wait()
					}

					if tagsToRefresh.isEmpty {
						return
					}

					var index = self.loadTagIndex(for: bookmark)
					for tag in tagsToRefresh {
						index = self.refreshFiles(for: tag, connection: connection, core: core, index: index)
					}
					self.saveTagIndex(index, for: bookmark)
					self.markSynced(bookmark: bookmark)
					self.postSyncDidFinish(for: bookmark)
				}
			}
		}
	}

	public func updateCachedSystemTags(_ tags: [OCSystemTag], for bookmark: OCBookmark) {
		saveCachedSystemTags(tags.filter(\.userVisible), for: bookmark)
	}

	public func cachedSystemTags(for bookmark: OCBookmark) -> [OCSystemTag]? {
		guard let data = OCAppIdentity.shared.userDefaults?.data(forKey: cachedTagsKey(for: bookmark)) else {
			return nil
		}
		guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
			return nil
		}
		return rows.compactMap { row in
			guard
				let identifier = row["id"] as? String,
				let displayName = row["name"] as? String
			else {
				return nil
			}
			let userVisible = (row["userVisible"] as? Bool) ?? true
			let userAssignable = (row["userAssignable"] as? Bool) ?? true
			return OCSystemTag(identifier: identifier, displayName: displayName, userVisible: userVisible, userAssignable: userAssignable)
		}
	}

	/// File IDs known to carry any of the selected tags (from the last account tag sync).
	public func fetchTaggedItems(
		selection tagIDs: Set<String>,
		tagNames: Set<String> = [],
		knownTags: [OCSystemTag] = [],
		core: OCCore,
		bookmark: OCBookmark
	) -> [OCItem] {
		let connection = core.connection
		let tagsToFetch = resolveTagsForRefresh(
			tagIDs: tagIDs,
			tagNames: tagNames,
			knownTags: knownTags,
			bookmark: bookmark
		)
		guard !tagsToFetch.isEmpty else {
			return []
		}

		var itemsByFileID: [String: OCItem] = [:]

		for tag in tagsToFetch {
			let (items, error) = retrieveFiles(with: tag, connection: connection)
			if error != nil {
				Log.error("Fetch tagged items failed tag=\(tag.displayName): \(String(describing: error))")
				continue
			}

			for item in items ?? [] {
				guard let fileID = item.fileID, !fileID.isEmpty else { continue }
				itemsByFileID[fileID] = item
			}
		}

		return Array(itemsByFileID.values)
	}

	public func fileIDs(
		forTagSelection tagIDs: Set<String>,
		tagNames: Set<String>,
		bookmark: OCBookmark,
		knownTags: [OCSystemTag] = []
	) -> Set<String> {
		let index = loadTagIndex(for: bookmark)
		let resolvedTagIDs = resolvedServerTagIDs(
			tagIDs: tagIDs,
			tagNames: tagNames,
			knownTags: knownTags,
			bookmark: bookmark
		)

		var fileIDs: Set<String> = []
		for tagID in resolvedTagIDs {
			fileIDs.formUnion(index[tagID] ?? [])
		}

		return fileIDs
	}

	public func shouldSync(bookmark: OCBookmark) -> Bool {
		guard let lastSync = lastSyncDate(for: bookmark) else {
			return true
		}
		return Date().timeIntervalSince(lastSync) >= Self.defaultSyncInterval
	}

	// MARK: - Tag resolution

	private func resolveTagsForRefresh(
		tagIDs: Set<String>,
		tagNames: Set<String>,
		knownTags: [OCSystemTag],
		bookmark: OCBookmark
	) -> [OCSystemTag] {
		let resolvedIDs = resolvedServerTagIDs(
			tagIDs: tagIDs,
			tagNames: tagNames,
			knownTags: knownTags,
			bookmark: bookmark
		)
		let allTags = mergedTagCatalog(cached: cachedSystemTags(for: bookmark) ?? [], known: knownTags)
		var tagsToRefresh: [OCSystemTag] = []
		var seenIDs: Set<String> = []

		for tagID in resolvedIDs {
			guard !seenIDs.contains(tagID), let tag = allTags.first(where: { $0.identifier == tagID }) else {
				continue
			}
			tagsToRefresh.append(tag)
			seenIDs.insert(tagID)
		}

		return tagsToRefresh
	}

	private func resolvedServerTagIDs(
		tagIDs: Set<String>,
		tagNames: Set<String>,
		knownTags: [OCSystemTag],
		bookmark: OCBookmark
	) -> Set<String> {
		let allTags = mergedTagCatalog(cached: cachedSystemTags(for: bookmark) ?? [], known: knownTags)
		var resolvedTagIDs = Set(tagIDs.filter { !$0.hasPrefix("local:") })

		for tagName in tagNames {
			if let tag = allTags.first(where: {
				$0.displayName.compare(tagName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
			}) {
				resolvedTagIDs.insert(tag.identifier)
			}
		}

		return resolvedTagIDs
	}

	private func mergedTagCatalog(cached: [OCSystemTag], known: [OCSystemTag]) -> [OCSystemTag] {
		var mergedByID: [String: OCSystemTag] = [:]

		for tag in cached + known {
			if tag.identifier.hasPrefix("local:") {
				continue
			}
			if let existingTag = mergedByID[tag.identifier] {
				if existingTag.displayName.isEmpty, !tag.displayName.isEmpty {
					mergedByID[tag.identifier] = tag
				}
			} else {
				mergedByID[tag.identifier] = tag
			}
		}

		return Array(mergedByID.values)
	}

	// MARK: - Sync implementation

	private func performSync(core: OCCore, bookmark: OCBookmark, completion: @escaping () -> Void) {
		let connection = core.connection

		let semaphore = DispatchSemaphore(value: 0)
		var systemTags: [OCSystemTag]?
		var systemTagsError: Error?

		connection.retrieveSystemTags { error, tags in
			systemTagsError = error
			systemTags = tags
			semaphore.signal()
		}
		semaphore.wait()

		if let systemTagsError {
			Log.error("retrieveSystemTags failed for \(bookmark): \(systemTagsError)")
			completion()
			return
		}

		let visibleTags = (systemTags ?? []).filter(\.userVisible)
		saveCachedSystemTags(visibleTags, for: bookmark)

		var index = loadTagIndex(for: bookmark)
		for tag in visibleTags {
			index = refreshFiles(for: tag, connection: connection, core: core, index: index)
		}

		// Drop associations for tags that no longer exist on the server.
		let visibleTagIDs = Set(visibleTags.map(\.identifier))
		let staleTagIDs = Set(index.keys).subtracting(visibleTagIDs)
		for staleTagID in staleTagIDs {
			index.removeValue(forKey: staleTagID)
		}

		saveTagIndex(index, for: bookmark)
		markSynced(bookmark: bookmark)
		postSyncDidFinish(for: bookmark)
		completion()
	}

	private func postSyncDidFinish(for bookmark: OCBookmark) {
		DispatchQueue.main.async {
			NotificationCenter.default.post(
				name: .accountTagSyncDidFinish,
				object: self,
				userInfo: [Self.bookmarkUserInfoKey: bookmark]
			)
		}
	}

	@discardableResult
	private func refreshFiles(
		for tag: OCSystemTag,
		connection: OCConnection,
		core: OCCore,
		index: [String: Set<String>]
	) -> [String: Set<String>] {
		let (items, error) = retrieveFiles(with: tag, connection: connection)
		if let error {
			Log.error("retrieveFiles failed tag=\(tag.displayName): \(error)")
			return index
		}

		let newFileIDs = Set((items ?? []).compactMap(\.fileID).filter { !$0.isEmpty })
		var updatedIndex = index
		let previousFileIDs = updatedIndex[tag.identifier] ?? []
		let removedFileIDs = previousFileIDs.subtracting(newFileIDs)

		updatedIndex[tag.identifier] = newFileIDs
		return updatedIndex
	}

	private func retrieveFiles(with tag: OCSystemTag, connection: OCConnection) -> ([OCItem]?, Error?) {
		let semaphore = DispatchSemaphore(value: 0)
		var resultItems: [OCItem]?
		var resultError: Error?

		let eventTarget = OCEventTarget(ephermalEventHandlerBlock: { event, _ in
			if let error = event.error {
				resultError = error
			} else if let items = event.result as? [OCItem] {
				resultItems = items
			}
			semaphore.signal()
		}, userInfo: nil, ephermalUserInfo: nil)

		connection.retrieveFiles(with: tag, resultTarget: eventTarget)
		semaphore.wait()
		return (resultItems, resultError)
	}

	// MARK: - Persistence

	private func saveCachedSystemTags(_ tags: [OCSystemTag], for bookmark: OCBookmark) {
		let rows: [[String: Any]] = tags.map {
			[
				"id": $0.identifier,
				"name": $0.displayName,
				"userVisible": $0.userVisible,
				"userAssignable": $0.userAssignable
			]
		}
		if let data = try? JSONSerialization.data(withJSONObject: rows) {
			OCAppIdentity.shared.userDefaults?.set(data, forKey: cachedTagsKey(for: bookmark))
		}
	}

	private func loadTagIndex(for bookmark: OCBookmark) -> [String: Set<String>] {
		guard let data = OCAppIdentity.shared.userDefaults?.data(forKey: tagIndexKey(for: bookmark)),
		      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
			return [:]
		}
		var index: [String: Set<String>] = [:]
		for (tagID, fileIDs) in raw {
			index[tagID] = Set(fileIDs)
		}
		return index
	}

	private func saveTagIndex(_ index: [String: Set<String>], for bookmark: OCBookmark) {
		var raw: [String: [String]] = [:]
		for (tagID, fileIDs) in index {
			raw[tagID] = Array(fileIDs)
		}
		if let data = try? JSONSerialization.data(withJSONObject: raw) {
			OCAppIdentity.shared.userDefaults?.set(data, forKey: tagIndexKey(for: bookmark))
		}
	}

	private func lastSyncDate(for bookmark: OCBookmark) -> Date? {
		let interval = OCAppIdentity.shared.userDefaults?.double(forKey: lastSyncKey(for: bookmark))
		guard let interval, interval > 0 else { return nil }
		return Date(timeIntervalSince1970: interval)
	}

	private func markSynced(bookmark: OCBookmark) {
		OCAppIdentity.shared.userDefaults?.set(Date().timeIntervalSince1970, forKey: lastSyncKey(for: bookmark))
	}

	private func bookmarkStorageKey(_ bookmark: OCBookmark) -> String {
		bookmark.uuid.uuidString
	}

	private func lastSyncKey(for bookmark: OCBookmark) -> String {
		lastSyncKeyPrefix + bookmarkStorageKey(bookmark)
	}

	private func cachedTagsKey(for bookmark: OCBookmark) -> String {
		cachedTagsKeyPrefix + bookmarkStorageKey(bookmark)
	}

	private func tagIndexKey(for bookmark: OCBookmark) -> String {
		tagIndexKeyPrefix + bookmarkStorageKey(bookmark)
	}

	// MARK: - In-flight guard

	private func beginSync(for bookmarkKey: String) -> Bool {
		inFlightLock.lock()
		defer { inFlightLock.unlock() }
		if inFlightBookmarkKeys.contains(bookmarkKey) {
			return false
		}
		inFlightBookmarkKeys.insert(bookmarkKey)
		return true
	}

	private func endSync(for bookmarkKey: String) {
		inFlightLock.lock()
		inFlightBookmarkKeys.remove(bookmarkKey)
		inFlightLock.unlock()
	}
}
