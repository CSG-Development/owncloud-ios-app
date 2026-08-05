import Foundation
import ownCloudSDK

/// Owns query subscription / KVO and materializes file-list items for the collection snapshot.
final class FileListQueryBridge {
	private(set) var items: [OCItem] = []
	private(set) var itemsByID: [String: OCItem] = [:]
	private(set) var folderStatistics: OCStatistic?

	/// Sort changes should reorder without diffable animations.
	var suppressNextSnapshotAnimation = false

	/// Called after items are rebuilt from the query datasource.
	var onItemsUpdated: ((_ updatedItemIDs: [String], _ animated: Bool) -> Void)?
	/// Root item / location-affecting query changes.
	var onQueryRootItemChanged: (() -> Void)?
	var onNeedsContentStateRecompute: (() -> Void)?
	var onRefreshControlShouldEnd: (() -> Void)?

	private var dataSourceSubscription: OCDataSourceSubscription?
	private var queryStateObservation: NSKeyValueObservation?
	private var queryRootItemObservation: NSKeyValueObservation?
	private var coreConnectionStatusObservation: NSKeyValueObservation?

	func item(for id: String) -> OCItem? {
		itemsByID[id]
	}

	static func itemIdentifier(for item: OCItem) -> String {
		if let localID = item.localID as String? {
			return localID
		}
		if let fileID = item.fileID {
			return fileID
		}
		return item.path ?? item.name ?? UUID().uuidString
	}

	func subscribe(to query: OCQuery?) {
		guard let dataSource = query?.queryResultsDataSource else { return }

		dataSourceSubscription?.terminate()
		dataSourceSubscription = dataSource.subscribe(updateHandler: { [weak self] subscription in
			self?.handleDataSourceUpdate(from: subscription)
		}, on: .main, trackDifferences: true, performInitialUpdate: true)
	}

	func observe(query: OCQuery?, clientContext: ClientContext?) {
		queryStateObservation?.invalidate()
		queryRootItemObservation?.invalidate()
		coreConnectionStatusObservation?.invalidate()

		queryStateObservation = query?.observe(\OCQuery.state, options: []) { [weak self] query, _ in
			OnMainThread {
				if query.state == .idle || clientContext?.core?.connectionStatus != .online {
					self?.onRefreshControlShouldEnd?()
				}
				self?.onNeedsContentStateRecompute?()
			}
		}

		queryRootItemObservation = query?.observe(\OCQuery.rootItem, options: []) { [weak self] query, _ in
			OnMainThread {
				clientContext?.rootItem = query.rootItem
				self?.onQueryRootItemChanged?()
			}
		}

		coreConnectionStatusObservation = clientContext?.core?.observe(\OCCore.connectionStatus, options: []) { [weak self] _, _ in
			OnMainThread {
				self?.onNeedsContentStateRecompute?()
			}
		}
	}

	func terminate() {
		dataSourceSubscription?.terminate()
		dataSourceSubscription = nil
		queryStateObservation?.invalidate()
		queryRootItemObservation?.invalidate()
		coreConnectionStatusObservation?.invalidate()
		queryStateObservation = nil
		queryRootItemObservation = nil
		coreConnectionStatusObservation = nil
	}

	private func handleDataSourceUpdate(from subscription: OCDataSourceSubscription) {
		let datasourceSnapshot = subscription.snapshotResettingChangeTracking(true)
		var nextItems: [OCItem] = []
		var nextByID: [String: OCItem] = [:]
		var itemIDByDataRef: [OCDataItemReference: String] = [:]
		// Track insertion order indexes so we can replace an earlier duplicate in place
		// (query results after decompress can briefly list the same localID twice —
		// placeholder + resolved item, or overlapping datasource emissions).
		var indexByID: [String: Int] = [:]

		for itemRef in datasourceSnapshot.items {
			guard let record = try? subscription.source?.record(forItemRef: itemRef),
			      let item = record.item as? OCItem else { continue }
			let id = Self.itemIdentifier(for: item)
			itemIDByDataRef[itemRef] = id
			nextByID[id] = item
			if let existingIndex = indexByID[id] {
				nextItems[existingIndex] = item
			} else {
				indexByID[id] = nextItems.count
				nextItems.append(item)
			}
		}

		let updatedItemIDs: [String] = {
			guard let updatedItems = datasourceSnapshot.updatedItems, !updatedItems.isEmpty else { return [] }
			return Array(Set(updatedItems.compactMap { itemIDByDataRef[$0] }))
		}()

		items = nextItems
		itemsByID = nextByID
		folderStatistics = datasourceSnapshot.specialItems?[.folderStatistics] as? OCStatistic

		let animated = !suppressNextSnapshotAnimation
		suppressNextSnapshotAnimation = false
		onItemsUpdated?(updatedItemIDs, animated)
		onNeedsContentStateRecompute?()
	}

	deinit {
		terminate()
	}
}
