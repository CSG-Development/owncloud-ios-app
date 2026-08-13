import UIKit
import ownCloudSDK

/// Multi-select mode: selection set, actions datasource, and actions-bar presentation.
final class FileListMultiSelectController {
	private(set) var isActive = false
	private(set) var selectedItemIDs = Set<String>()

	private var actionContext: ActionContext?
	private var actionsDatasource: OCDataSourceArray?
	private var noActionsTextItem: OCDataItemPresentable?

	/// Fired when an applicable action completes and selection mode should end.
	var onActionCompleted: (() -> Void)?
	/// Fired when nav chrome / visible cells should refresh for selection changes.
	var onSelectionChanged: (() -> Void)?

	func setActive(
		_ selecting: Bool,
		host: UIViewController,
		clientContext: ClientContext?,
		query: OCQuery?,
		items: [OCItem],
		actionsBar: FileListActionsBarController,
		collectionView: UICollectionView,
		itemIdentifier: (OCItem) -> String,
		applySelectionUI: (_ fileIDs: [String]) -> Void
	) {
		guard selecting != isActive else { return }
		isActive = selecting
		collectionView.allowsMultipleSelection = selecting
		selectedItemIDs.removeAll()
		collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false) }

		if selecting {
			actionsBar.close()
			if let core = clientContext?.core {
				let actionsLocation = OCExtensionLocation(ofType: .action, identifier: .multiSelection)
				actionContext = ActionContext(viewController: host, clientContext: clientContext, core: core, query: query, items: [], location: actionsLocation)
			}
			actionsDatasource = OCDataSourceArray()
			actionsDatasource?.trackItemVersions = true
			refreshActions()
			if let actionsDatasource {
				actionsBar.show(with: actionsDatasource, clientContext: clientContext)
			}
		} else {
			actionsBar.close()
			actionsDatasource = nil
			actionContext = nil
		}

		applySelectionUI(items.map(itemIdentifier))
	}

	func refreshActions() {
		guard let actionContext else { return }

		var actionItems: [OCDataItem & OCDataItemVersioning] = []
		let actionCompletionHandler: ActionCompletionHandler = { [weak self] _, _ in
			OnMainThread {
				self?.onActionCompleted?()
			}
		}

		if actionContext.items.isEmpty {
			if noActionsTextItem == nil {
				noActionsTextItem = OCDataItemPresentable(reference: "_emptyActionList" as NSString, originalDataItemType: nil, version: nil)
				noActionsTextItem?.title = OCLocalizedString("Select one or more items.", nil)
				noActionsTextItem?.childrenDataSourceProvider = nil
			}

			if let noActionsTextItem {
				noActionsTextItem.dataItemVersion = "empty" as NSString
				actionItems = [noActionsTextItem]
			}
		} else {
			let selectionVersion = actionContext.items
				.compactMap { $0.localID as String? }
				.sorted()
				.joined(separator: ",")
			let actions = Action.sortedApplicableActions(for: actionContext)
			for action in actions {
				action.completionHandler = actionCompletionHandler
				let ocAction = action.provideOCAction(singleVersion: true)
				// Include selection fingerprint so the actions bar refreshes when
				// the selected set changes even if action identifiers stay the same.
				ocAction.version = "\(ocAction.identifier ?? "")|\(selectionVersion)"
				actionItems.append(ocAction)
			}
		}

		if actionsDatasource?.trackItemVersions != true {
			actionsDatasource?.trackItemVersions = true
		}
		actionsDatasource?.setVersionedItems(actionItems)
	}

	func select(itemID: String, item: OCItem, restoring: Bool) {
		guard isActive, !restoring else { return }
		selectedItemIDs.insert(itemID)
		actionContext?.add(item: item)
		refreshActions()
		onSelectionChanged?()
	}

	func deselect(itemID: String, item: OCItem) {
		guard isActive else { return }
		selectedItemIDs.remove(itemID)
		actionContext?.remove(item: item)
		refreshActions()
		onSelectionChanged?()
	}

	func selectDeselectAll(
		items: [OCItem],
		itemIdentifier: (OCItem) -> String,
		collectionView: UICollectionView
	) {
		if selectedItemIDs.count == items.count {
			selectedItemIDs.removeAll()
			actionContext?.replace(items: [])
			collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false) }
		} else {
			selectedItemIDs = Set(items.map(itemIdentifier))
			actionContext?.replace(items: items)
			for (index, _) in items.enumerated() {
				collectionView.selectItem(at: IndexPath(item: index, section: FileListSection.files.rawValue), animated: false, scrollPosition: [])
			}
		}
		refreshActions()
		onSelectionChanged?()
	}

	func restoreSelectionIfNeeded(
		in collectionView: UICollectionView,
		indexPathForItemID: (String) -> IndexPath?
	) {
		guard isActive, !selectedItemIDs.isEmpty else { return }
		for itemID in selectedItemIDs {
			guard let indexPath = indexPathForItemID(itemID) else { continue }
			collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
		}
	}
}
