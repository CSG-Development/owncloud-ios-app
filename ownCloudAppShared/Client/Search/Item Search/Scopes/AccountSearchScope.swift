//
//  AccountSearchScope.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 25.08.22.
//  Copyright © 2022 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2022, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import ownCloudSDK
import ownCloudApp

// Search scope that creates and manages its own OCQuery using OCQueryConditions
// Used for account-wide search (local OCQuery path), not server-side KQL search

open class CustomQuerySearchScope : ItemSearchScope {
	private let maxResultCountDefault = 100 // Maximum number of results to return from database (default)
 	private var maxResultCount = 100 // Maximum number of results to return from database (flexible)

	public override var isSelected: Bool {
		didSet {
			if isSelected {
				resultActionSource.setItems([
					OCAction(title: OCLocalizedString("Show more results", nil), icon: nil, action: { [weak self] action, options, completion in
						self?.showMoreResults()
						completion(nil)
					})
				], updated: nil)
				composeResultsDataSource()
			}
		}
	}

	public var resultActionSource: OCDataSourceArray = OCDataSourceArray()

	var resultsSubscription: OCDataSourceSubscription?

	func composeResultsDataSource() {
		if let queryResultsSource = customQuery?.queryResultsDataSource {
			let composedResults = OCDataSourceComposition(sources: [
				queryResultsSource,
				resultActionSource
			])

			let maxResultCount = maxResultCount
			let resultActionSource = resultActionSource

			resultsSubscription = queryResultsSource.subscribe(updateHandler: { [weak composedResults, weak resultActionSource] (subscription) in
				let snapshot = subscription.snapshotResettingChangeTracking(true)

				if let resultActionSource = resultActionSource {
					OnMainThread {
						composedResults?.setInclude((snapshot.numberOfItems >= maxResultCount), for: resultActionSource)
					}
				}
			}, on: .main, trackDifferences: false, performInitialUpdate: true)

			results = composedResults
		} else {
			results = nil
		}
	}

	public var customQuery: OCQuery? {
		willSet {
			customQuery?.delegate = nil
			if let core = clientContext.core, let oldQuery = customQuery {
				core.stop(oldQuery)
			}
		}

		didSet {
			customQuery?.delegate = self

			if let core = clientContext.core, let newQuery = customQuery {
				core.start(newQuery)

				composeResultsDataSource()
			} else {
				results = nil
			}
		}
	}

	public var queryConditionModifier : ((OCQueryCondition?) -> OCQueryCondition?)?  // MARK: modifier that can modify the query condition before it is passed to create the OCQuery backing the scope. The modification is invisible to the outside. Can be used to add constraints like limit to a drive, etc.

	public var additionalRequirementCondition: OCQueryCondition? // MARK: Adds a required additional condition to the baseCondition

	private var lastSearchTerm : String?
	private var scrollToTopWithNextRefresh : Bool = false

	private func mergedFilterCondition(from baseCondition: OCQueryCondition?, includeScopeConstraintsForTagOnly: Bool = false) -> OCQueryCondition? {
		var condition = baseCondition

		if let additionalRequirementCondition {
			if let baseCondition = condition {
				condition = .require([additionalRequirementCondition, baseCondition])
			} else if includeScopeConstraintsForTagOnly {
				// Wrap scope constraints so sort/limit metadata never sticks on the shared instance.
				condition = .require([additionalRequirementCondition])
			}
		}

		if let queryConditionModifier, let baseCondition = condition {
			condition = queryConditionModifier(baseCondition)
		}

		return condition
	}

	private func clearQueryExecutionMetadata(from condition: OCQueryCondition?) {
		condition?.sortBy = nil
		condition?.sortAscending = true
		condition?.maxResultCount = nil
	}

 	public func updateCustomSearchQuery() {
		clearQueryExecutionMetadata(from: additionalRequirementCondition)
		if lastSearchTerm != searchTerm {
			// Reset max result count when search text changes
			maxResultCount = maxResultCountDefault
			lastSearchTerm = searchTerm

			// Scroll to top when search text changes
			scrollToTopWithNextRefresh = true
		}

		let hasTagFilter = !selectedTagIDs.isEmpty || !selectedTagNames.isEmpty
		let hasNonTagUserQuery = queryCondition != nil

		if hasTagFilter, let core = clientContext.core {
			var scopeCondition = mergedFilterCondition(
				from: queryCondition,
				includeScopeConstraintsForTagOnly: !hasNonTagUserQuery
			)

			if let sortDescriptor = clientContext.sortDescriptor {
				scopeCondition?.sortBy = sortDescriptor.method.sortPropertyName
				scopeCondition?.sortAscending = sortDescriptor.direction == .ascending
			}

			let configuration = LocalSearchFilterConfiguration(
				nonTagCondition: scopeCondition,
				selectedTagIDs: selectedTagIDs,
				selectedTagNames: selectedTagNames,
				maxResultCount: maxResultCount,
				allowUnknownTagPassThrough: false,
				bookmark: clientContext.accountConnection?.bookmark ?? core.bookmark,
				hasNonTagUserQuery: hasNonTagUserQuery
			)
			customQuery = LocalSearchFilterAdapter.makeQuery(core: core, configuration: configuration)
			return
		}

		var condition = mergedFilterCondition(from: queryCondition)

 		if let condition {
			if let sortDescriptor = clientContext.sortDescriptor {
				condition.sortBy = sortDescriptor.method.sortPropertyName
				condition.sortAscending = sortDescriptor.direction == .ascending
			}

			condition.maxResultCount = NSNumber(value: maxResultCount)
			customQuery = OCQuery(condition: condition, inputFilter: nil)
 		} else {
 			customQuery = nil
 		}
 	}

	func showMoreResults() {
		maxResultCount += maxResultCountDefault
		updateCustomSearchQuery()
	}

 	open override var queryCondition: OCQueryCondition? {
 		didSet {
 			updateCustomSearchQuery()
		}
	}

	open override func sortDescriptorChanged(to sortDescriptor: SortDescriptor?) {
		updateCustomSearchQuery()
	}

	/// Re-run the query when tag chips change without altering text/size/date conditions.
	open override func updateFor(_ searchElements: [SearchElement]) {
		super.updateFor(searchElements)
		if isSelected {
			updateCustomSearchQuery()
		}
	}
}

extension CustomQuerySearchScope: OCQueryDelegate {
	public func query(_ query: OCQuery, failedWithError error: Error) {
	}

	public func queryHasChangesAvailable(_ query: OCQuery) {
	}

	public func queryHasChangedState(_ query: OCQuery) {
		OnMainThread {
			self.searchViewController?.refreshCurrentContent()
		}
	}
}

// Subclasses
open class AccountSearchScope : CustomQuerySearchScope {
	open override class var descriptor: SearchScopeDescriptor {
		return SearchScopeDescriptor(identifier: "account", localizedName: OCLocalizedString("Account", nil), localizedDescription: OCLocalizedString("Searches the personal folder and all spaces.", nil), icon: OCSymbol.icon(forSymbolName: "person"), searchableContent: .itemName, scopeCreator: { (clientContext, cellStyle, descriptor) in
			if let cellStyle {
				let pathAndRevealCellStyle = CollectionViewCellStyle(from: cellStyle, changing: { cellStyle in
					cellStyle.showRevealButton = true
					cellStyle.showPathDetails = true
				})

				return AccountSearchScope(with: clientContext, cellStyle: pathAndRevealCellStyle, localizedName: descriptor.localizedName, localizedPlaceholder: OCLocalizedString("Search account", nil), icon: descriptor.icon)
			}
			return nil
		})
	}

	public override init(with context: ClientContext, cellStyle: CollectionViewCellStyle?, localizedName name: String, localizedPlaceholder placeholder: String? = nil, icon: UIImage? = nil) {
		var revealCellStyle : CollectionViewCellStyle?

		if let cellStyle = cellStyle {
			revealCellStyle = CollectionViewCellStyle(from: cellStyle, changing: { cellStyle in
				cellStyle.showRevealButton = true
			})
		}

		super.init(with: context, cellStyle: revealCellStyle, localizedName: name, localizedPlaceholder: placeholder, icon: icon)

		if let displaySettingsCondition = DisplaySettings.shared.queryConditionForDisplaySettings {
			additionalRequirementCondition = displaySettingsCondition
		}
	}

	open override var savedSearchScope: OCSavedSearchScope? {
		return .account
	}
}

open class DriveSearchScope : AccountSearchScope {
	open override class var descriptor: SearchScopeDescriptor {
		return SearchScopeDescriptor(identifier: "drive", localizedName: OCLocalizedString("Space", nil), localizedDescription: OCLocalizedString("Searches in the current space ONLY.", nil), icon: OCSymbol.icon(forSymbolName: "square.grid.2x2"), searchableContent: .itemName, scopeCreator: { (clientContext, cellStyle, descriptor) in
			if let cellStyle, clientContext.query?.queryLocation != nil {
				var placeholder = OCLocalizedString("Search space", nil)
				if let driveName = clientContext.drive?.name, driveName.count > 0 {
					placeholder = OCLocalizedFormat("Search {{space.name}}", ["space.name" : driveName])
				}
				return DriveSearchScope(with: clientContext, cellStyle: cellStyle, localizedName: descriptor.localizedName, localizedPlaceholder: placeholder, icon: descriptor.icon)
			}
			return nil
		})
	}

	private var driveID : String?

	public override init(with context: ClientContext, cellStyle: CollectionViewCellStyle?, localizedName name: String, localizedPlaceholder placeholder: String? = nil, icon: UIImage? = nil) {
		super.init(with: context, cellStyle: cellStyle, localizedName: name, localizedPlaceholder: placeholder, icon: icon)

		if context.core?.useDrives == true, let driveID = context.drive?.identifier {
			self.driveID = driveID
			let driveCondition = OCQueryCondition.where(.driveID, isEqualTo: driveID)

			if let displaySettingsCondition = DisplaySettings.shared.queryConditionForDisplaySettings {
				additionalRequirementCondition = .require([displaySettingsCondition, driveCondition])
			} else {
				additionalRequirementCondition = driveCondition
			}
		}
	}

	open override var savedSearchScope: OCSavedSearchScope? {
		return .drive
	}

	open override var savedSearch: AnyObject? {
		if let savedSearch = super.savedSearch as? OCSavedSearch {
			savedSearch.location = OCLocation(driveID: driveID, path: nil)
			return savedSearch
		}
		return nil
	}
}

open class ContainerSearchScope: AccountSearchScope {
	open override class var descriptor: SearchScopeDescriptor {
		return SearchScopeDescriptor(identifier: "tree", localizedName: OCLocalizedString("Tree", nil), localizedDescription: OCLocalizedString("Searches the current folder and its subfolders.", nil), icon: OCSymbol.icon(forSymbolName: "square.stack.3d.up"), searchableContent: .itemName, scopeCreator: { (clientContext, cellStyle, descriptor) in
			if let cellStyle, clientContext.query?.queryLocation != nil {
				var placeholder = OCLocalizedString("Search tree", nil)
				if let path = clientContext.query?.queryLocation?.lastPathComponent, path.count > 0 {
					placeholder = OCLocalizedFormat("Search from {{folder.name}}", ["folder.name" : path])
				}
				return ContainerSearchScope(with: clientContext, cellStyle: cellStyle, localizedName: descriptor.localizedName, localizedPlaceholder: placeholder, icon: descriptor.icon)
			}
			return nil
		})
	}

	private var location : OCLocation?

	public override init(with context: ClientContext, cellStyle: CollectionViewCellStyle?, localizedName name: String, localizedPlaceholder placeholder: String? = nil, icon: UIImage? = nil) {
		super.init(with: context, cellStyle: cellStyle, localizedName: name, localizedPlaceholder: placeholder, icon: icon)

		if context.core?.useDrives == true, let queryLocation = context.query?.queryLocation, let path = queryLocation.path {
			self.location = queryLocation
			var containerCondition: OCQueryCondition

			if context.core?.useDrives == true, let driveID = queryLocation.driveID {
				containerCondition = .require([
					.where(.driveID, isEqualTo: driveID),
					.where(.path, startsWith: path),
					.where(.path, isNotEqualTo: path)
				])
			} else {
				containerCondition = .require([
					.where(.path, startsWith: path),
					.where(.path, isNotEqualTo: path)
				])
			}

			if let displaySettingsCondition = DisplaySettings.shared.queryConditionForDisplaySettings {
				additionalRequirementCondition = .require([displaySettingsCondition, containerCondition])
			} else {
				additionalRequirementCondition = containerCondition
			}
		}
	}

	open override var savedSearchScope: OCSavedSearchScope? {
		return .container
	}

	open override var savedSearch: AnyObject? {
		if let savedSearch = super.savedSearch as? OCSavedSearch {
			savedSearch.location = location
			return savedSearch
		}
		return nil
	}

}

// MARK: - Local search filter adapter

struct LocalSearchFilterConfiguration {
	let nonTagCondition: OCQueryCondition?
	let selectedTagIDs: Set<String>
	let selectedTagNames: Set<String>
	let maxResultCount: Int?
	let allowUnknownTagPassThrough: Bool
	let bookmark: OCBookmark?
	/// True when the user entered text or chose a non-tag filter (type, date, size, …).
	let hasNonTagUserQuery: Bool

	var hasTagSelection: Bool {
		!selectedTagIDs.isEmpty || !selectedTagNames.isEmpty
	}
}

/// Tracks identities of items currently shown by a tag-filtered custom query so incremental
/// core updates can refresh existing rows without admitting unrelated items from sync.
private final class TagSearchResultIdentitySet {
	private var fileIDs: Set<String> = []
	private var localIDs: Set<String> = []
	private let lock = NSLock()

	func replace(with items: [OCItem]) {
		lock.lock()
		defer { lock.unlock() }

		fileIDs = Set(items.compactMap { item in
			guard let fileID = item.fileID, !fileID.isEmpty else { return nil }
			return fileID
		})
		localIDs = Set(items.compactMap { $0.localID as String? })
	}

	func contains(_ item: OCItem) -> Bool {
		lock.lock()
		defer { lock.unlock() }

		if let localID = item.localID as String?, localIDs.contains(localID) {
			return true
		}
		if let fileID = item.fileID, !fileID.isEmpty, fileIDs.contains(fileID) {
			return true
		}
		return false
	}
}

/// Centralizes local filtering: when tags are selected, start from tagged files, then apply other filters.
enum LocalSearchFilterAdapter {
	static func makeQuery(core: OCCore, configuration: LocalSearchFilterConfiguration) -> OCQuery {
		let resultIdentities = TagSearchResultIdentitySet()

		let customSource: OCQueryCustomSource = { core, query, resultHandler in
			DispatchQueue.global(qos: .userInitiated).async {
				let items = makeResults(core: core, configuration: configuration)
				if query.state == .stopped {
					return
				}
				resultIdentities.replace(with: items)
				resultHandler(nil, items)
			}
		}

		// Allow in-place updates for items already in this query, but reject unrelated items
		// that arrive from broad core sync while tag filtering is active.
		guard let stableResultFilter = OCQueryFilter(handler: { _, _, item in
			guard let item else { return false }
			return resultIdentities.contains(item)
		}) else {
			fatalError("Failed to create local search adapter query filter")
		}
		let query = OCQuery(customSource: customSource, inputFilter: stableResultFilter)
		if let comparator = configuration.nonTagCondition?.itemComparator() {
			query.sortComparator = comparator
		}
		return query
	}

	static func makeResults(core: OCCore, configuration: LocalSearchFilterConfiguration) -> [OCItem] {
		var candidates: [OCItem] = []
		var allowedTagFileIDs: Set<String> = []

		if configuration.hasTagSelection {
			allowedTagFileIDs = indexedFileIDs(for: configuration)
			candidates = gatherTaggedCandidates(
				core: core,
				configuration: configuration
			)
			if allowedTagFileIDs.isEmpty {
				allowedTagFileIDs = fileIDs(for: candidates)
			}
		} else if configuration.hasNonTagUserQuery, let nonTagCondition = configuration.nonTagCondition {
			candidates = gatherNonTagResults(core: core, condition: nonTagCondition)
		}

		var matched = filter(candidates, configuration: configuration, allowedTagFileIDs: allowedTagFileIDs)

		if let comparator = configuration.nonTagCondition?.itemComparator() {
			matched.sort { comparator($0, $1) == .orderedAscending }
		}

		if let maxResultCount = configuration.maxResultCount, matched.count > maxResultCount {
			return Array(matched.prefix(maxResultCount))
		}

		return matched
	}

	private static func gatherTaggedCandidates(
		core: OCCore,
		configuration: LocalSearchFilterConfiguration
	) -> [OCItem] {
		guard let bookmark = configuration.bookmark else {
			return []
		}

		let indexedFileIDs = AccountTagSyncService.shared.fileIDs(
			forTagSelection: configuration.selectedTagIDs,
			tagNames: configuration.selectedTagNames,
			bookmark: bookmark
		)
		if !indexedFileIDs.isEmpty {
			return fetchItems(forFileIDs: indexedFileIDs, core: core)
		}

		return AccountTagSyncService.shared.fetchTaggedItems(
			selection: configuration.selectedTagIDs,
			tagNames: configuration.selectedTagNames,
			core: core,
			bookmark: bookmark
		)
	}

	private static func fileIDs(for items: [OCItem]) -> Set<String> {
		Set(items.compactMap { item in
			guard let fileID = item.fileID, !fileID.isEmpty else { return nil }
			return fileID
		})
	}

	private static func indexedFileIDs(for configuration: LocalSearchFilterConfiguration) -> Set<String> {
		guard configuration.hasTagSelection, let bookmark = configuration.bookmark else {
			return []
		}

		return AccountTagSyncService.shared.fileIDs(
			forTagSelection: configuration.selectedTagIDs,
			tagNames: configuration.selectedTagNames,
			bookmark: bookmark
		)
	}

	private static func fetchItems(forFileIDs fileIDs: Set<String>, core: OCCore) -> [OCItem] {
		guard let database = core.vault.database, !fileIDs.isEmpty else {
			return []
		}

		var fetchedItems: [OCItem] = []
		for fileID in fileIDs {
			let semaphore = DispatchSemaphore(value: 0)
			database.retrieveCacheItem(forFileID: fileID) { _, _, _, item in
				if let item {
					fetchedItems.append(item)
				}
				semaphore.signal()
			}
			semaphore.wait()
		}

		return uniqueItems(fetchedItems)
	}

	private static func gatherNonTagResults(core: OCCore, condition: OCQueryCondition?) -> [OCItem] {
		guard let database = core.vault.database else { return [] }

		let fetchCondition = condition ?? .where(.name, contains: "")
		let originalMaxResultCount = fetchCondition.maxResultCount
		fetchCondition.maxResultCount = nil

		let semaphore = DispatchSemaphore(value: 0)
		var fetchedItems: [OCItem] = []

		database.retrieveCacheItems(for: fetchCondition, cancelAction: nil) { _, _, _, items in
			fetchedItems = items ?? []
			semaphore.signal()
		}
		semaphore.wait()
		fetchCondition.maxResultCount = originalMaxResultCount

		return uniqueItems(fetchedItems)
	}

	static func filter(_ items: [OCItem], configuration: LocalSearchFilterConfiguration, allowedTagFileIDs: Set<String> = []) -> [OCItem] {
		let filteredItems = items.filter { item in
			if let nonTagCondition = configuration.nonTagCondition, !nonTagCondition.fulfilled(by: item) {
				return false
			}

			guard configuration.hasTagSelection else {
				return true
			}

			guard let fileID = item.fileID, !fileID.isEmpty else {
				return false
			}
			return allowedTagFileIDs.contains(fileID)
		}

		return uniqueItems(filteredItems)
	}

	static func uniqueItems(_ items: [OCItem]) -> [OCItem] {
		var seenFileIDs: Set<String> = []
		var seenPathKeys: Set<String> = []
		var uniqueItems: [OCItem] = []

		for item in items {
			if let fileID = item.fileID, !fileID.isEmpty {
				guard !seenFileIDs.contains(fileID) else { continue }
				seenFileIDs.insert(fileID)
				seenPathKeys.insert(pathIdentityKey(for: item))
				uniqueItems.append(item)
				continue
			}

			let pathKey = pathIdentityKey(for: item)
			guard !seenPathKeys.contains(pathKey) else { continue }
			seenPathKeys.insert(pathKey)
			uniqueItems.append(item)
		}

		return uniqueItems
	}

	private static func pathIdentityKey(for item: OCItem) -> String {
		let driveID = item.location?.driveID ?? item.driveID ?? ""
		let path = item.location?.path ?? item.path ?? ""
		return "\(driveID):\(path)"
	}
}

public extension SearchScopeDescriptor {
	static var tree = ContainerSearchScope.descriptor
	static var drive = DriveSearchScope.descriptor
	static var account = AccountSearchScope.descriptor
}
