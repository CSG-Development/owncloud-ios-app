import UIKit
import ownCloudSDK
import ownCloudApp

struct SidebarMenuEntry {
	enum Kind: Equatable {
		case action
		case folder
	}

	let itemReference: OCDataItemReference
	let item: OCDataItem
	let title: String
	let icon: UIImage?
	let kind: Kind
	let indentLevel: Int
	let children: [SidebarMenuEntry]?
}

enum SidebarMenuBuilder {
	static func entries(for accountController: AccountController, expandedFolderRefs: [OCDataItemReference]) -> [SidebarMenuEntry] {
		guard let itemsDataSource = accountController.itemsDataSource as? OCDataSource else { return [] }

		var result: [SidebarMenuEntry] = []

		for itemRef in orderedItemReferences(in: itemsDataSource) {
			guard let record = try? itemsDataSource.record(forItemRef: itemRef) else { continue }
			result.append(contentsOf: entries(for: record, dataSource: itemsDataSource, indentLevel: 0, expandedFolderRefs: expandedFolderRefs))
		}

		return result
	}

	static func entries(
		for action: OCAction,
		itemReference: OCDataItemReference = "_action_\(UUID().uuidString)" as NSString
	) -> SidebarMenuEntry {
		SidebarMenuEntry(
			itemReference: itemReference,
			item: action,
			title: action.title ?? "",
			icon: action.icon,
			kind: .action,
			indentLevel: 0,
			children: nil
		)
	}

	private static func orderedItemReferences(in dataSource: OCDataSource) -> [OCDataItemReference] {
		let subscription = dataSource.subscribe(updateHandler: { _ in }, on: nil, trackDifferences: false, performInitialUpdate: true)
		let items = subscription.snapshotResettingChangeTracking(false).items
		subscription.terminate()
		return items
	}

	private static func entries(
		for record: OCDataItemRecord,
		dataSource: OCDataSource,
		indentLevel: Int,
		expandedFolderRefs: [OCDataItemReference]
	) -> [SidebarMenuEntry] {
		guard let item = record.item else { return [] }

		let presentation = presentable(for: item)
		let hasChildren = record.hasChildren || (item as? CollectionSidebarAction)?.childrenDataSource != nil

		if hasChildren, let childrenDataSource = item.dataSourceForChildren?(using: dataSource) ?? (item as? CollectionSidebarAction)?.childrenDataSource {
			let children = childEntries(from: childrenDataSource, parentDataSource: dataSource, indentLevel: indentLevel + 1)
			let entry = SidebarMenuEntry(
				itemReference: item.dataItemReference,
				item: item,
				title: presentation.title,
				icon: presentation.icon,
				kind: .folder,
				indentLevel: indentLevel,
				children: children
			)

			if expandedFolderRefs.contains(where: { $0.isEqual(item.dataItemReference) }) {
				return [entry] + children
			}
			return [entry]
		}

		return [
			SidebarMenuEntry(
				itemReference: item.dataItemReference,
				item: item,
				title: presentation.title,
				icon: presentation.icon,
				kind: .action,
				indentLevel: indentLevel,
				children: nil
			)
		]
	}

	private static func childEntries(
		from childrenDataSource: OCDataSource,
		parentDataSource: OCDataSource,
		indentLevel: Int
	) -> [SidebarMenuEntry] {
		var result: [SidebarMenuEntry] = []

		for itemRef in orderedItemReferences(in: childrenDataSource) {
			guard let record = try? childrenDataSource.record(forItemRef: itemRef) else { continue }
			result.append(contentsOf: entries(for: record, dataSource: parentDataSource, indentLevel: indentLevel, expandedFolderRefs: []))
		}

		return result
	}

	private static func presentable(for item: OCDataItem) -> (title: String, icon: UIImage?) {
		if let action = item as? OCAction {
			return (action.title ?? "", action.icon)
		}

		if let savedSearch = item as? OCSavedSearch {
			var icon: UIImage?
			if let customIconName = savedSearch.customIconName {
				icon = OCSymbol.icon(forSymbolName: customIconName) ?? UIImage(named: customIconName, in: Bundle.sharedAppBundle, with: nil)
			}
			if icon == nil {
				icon = savedSearch.isTemplate ? SavedSearchCell.savedTemplateIcon : SavedSearchCell.savedSearchIcon
			}
			return (savedSearch.sideBarDisplayName, icon)
		}

		if let presentable = OCDataRenderer.default.renderItem(item, asType: .presentable, error: nil, withOptions: nil) as? OCDataItemPresentable {
			return (presentable.title ?? "", presentable.image)
		}

		if let sidebarItem = OCDataRenderer.default.renderItem(item, asType: .sidebarItem, error: nil, withOptions: nil) as? OCSidebarItem {
			return (sidebarItem.location?.displayName(in: nil) ?? "", OCSymbol.icon(forSymbolName: "folder"))
		}

		return ("", nil)
	}
}
