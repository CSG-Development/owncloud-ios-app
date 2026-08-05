import UIKit
import ownCloudSDK

/// Drag, drop, and drop-target actions-bar presentation for the file list.
final class FileListDragDropController {
	private weak var host: UIViewController?
	private weak var actionsBar: FileListActionsBarController?
	private var clientContextProvider: (() -> ClientContext?)?
	private var isMultiSelectingProvider: (() -> Bool)?
	private var itemProvider: ((IndexPath) -> (id: String, item: OCItem)?)?

	private var dropTargetsDataSource: OCDataSourceArray?
	private var dropTargetsActionContext: ActionContext?
	private var lastDropProposalDestinationIndexPath: IndexPath?

	func configure(
		host: UIViewController,
		actionsBar: FileListActionsBarController,
		clientContext: @escaping () -> ClientContext?,
		isMultiSelecting: @escaping () -> Bool,
		itemAt: @escaping (IndexPath) -> (id: String, item: OCItem)?
	) {
		self.host = host
		self.actionsBar = actionsBar
		self.clientContextProvider = clientContext
		self.isMultiSelectingProvider = isMultiSelecting
		self.itemProvider = itemAt
	}

	private var clientContext: ClientContext? { clientContextProvider?() }
	private var isMultiSelecting: Bool { isMultiSelectingProvider?() ?? false }

	func clearDropTargetsSideState() {
		dropTargetsDataSource = nil
	}

	// MARK: - UICollectionViewDragDelegate

	func dragItems(at indexPath: IndexPath) -> [UIDragItem] {
		guard !isMultiSelecting,
		      let entry = itemProvider?(indexPath),
		      !FileListItemID.isActivity(entry.id),
		      let item = entry.item as? DataItemDragInteraction else { return [] }
		return item.provideDragItems(with: clientContext) ?? []
	}

	// MARK: - UICollectionViewDropDelegate

	func canHandle(_ session: UIDropSession) -> Bool {
		canProvideDropTargets(for: session)
	}

	func dropProposal(for session: UIDropSession, destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		lastDropProposalDestinationIndexPath = destinationIndexPath
		updateDropTargets(for: session)

		if let destinationIndexPath,
		   let entry = itemProvider?(destinationIndexPath),
		   !FileListItemID.isActivity(entry.id),
		   let item = entry.item as? DataItemDropInteraction,
		   let proposal = item.allowDropOperation?(for: session, with: clientContext) {
			return proposal
		}

		if clientContext?.rootItem is DataItemDropInteraction {
			return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
		}

		return UICollectionViewDropProposal(operation: .cancel)
	}

	func performDrop(with coordinator: UICollectionViewDropCoordinator, collectionView: UICollectionView) {
		let destinationIndexPath = coordinator.destinationIndexPath ?? lastDropProposalDestinationIndexPath
		var dropInteraction: DataItemDropInteraction?
		let dragItems = coordinator.items.map(\.dragItem)

		if let destinationIndexPath,
		   let entry = itemProvider?(destinationIndexPath),
		   !FileListItemID.isActivity(entry.id),
		   let item = entry.item as? DataItemDropInteraction {
			dropInteraction = item
		} else {
			dropInteraction = clientContext?.rootItem as? DataItemDropInteraction
		}

		dropInteraction?.performDropOperation(of: dragItems, with: clientContext) { _ in }
		cleanupDropTargets(for: coordinator.session)
	}

	func dropSessionDidEnd(_ session: UIDropSession) {
		cleanupDropTargets(for: session)
	}

	// MARK: - DropTargetsProvider

	func canProvideDropTargets(for dropSession: UIDropSession) -> Bool {
		for item in dropSession.items {
			if item.localObject == nil, item.itemProvider.hasItemConformingToTypeIdentifier("public.folder") {
				return false
			} else if let localDataItem = item.localObject as? LocalDataItem,
			          clientContext?.core?.bookmark.uuid != localDataItem.bookmarkUUID,
			          (localDataItem.dataItem as? OCItem)?.type == .collection {
				return false
			}
		}

		if dropSession.localDragSession != nil {
			return !provideDropItems(from: dropSession).isEmpty
		}
		return true
	}

	func provideDropTargets(for dropSession: UIDropSession) -> [OCDataItem & OCDataItemVersioning]? {
		let items = provideDropItems(from: dropSession)
		guard !items.isEmpty, let core = clientContext?.core, let host else { return nil }
		dropTargetsActionContext = ActionContext(viewController: host, clientContext: clientContext, core: core, items: items, location: OCExtensionLocation(ofType: .action, identifier: .dropAction))
		guard let dropTargetsActionContext else { return nil }
		return Action.sortedApplicableActions(for: dropTargetsActionContext).map { $0.provideOCAction(singleVersion: true) }
	}

	func cleanupDropTargets(for dropSession: UIDropSession) {
		dropTargetsActionContext = nil
		if !isMultiSelecting {
			actionsBar?.close()
			dropTargetsDataSource = nil
		}
	}

	// MARK: - Private

	private func provideDropItems(from dropSession: UIDropSession) -> [OCItem] {
		var items: [OCItem] = []
		var allItemsFromSameAccount = true

		guard let bookmarkUUID = clientContext?.core?.bookmark.uuid else { return [] }

		for dragItem in dropSession.items {
			if let localDataItem = dragItem.localObject as? LocalDataItem {
				if localDataItem.bookmarkUUID != bookmarkUUID {
					allItemsFromSameAccount = false
					break
				} else if let item = localDataItem.dataItem as? OCItem {
					items.append(item)
				}
			} else {
				allItemsFromSameAccount = false
				break
			}
		}

		return allItemsFromSameAccount ? items : []
	}

	private func updateDropTargets(for session: UIDropSession) {
		guard !isMultiSelecting,
		      let targets = provideDropTargets(for: session),
		      !targets.isEmpty,
		      let actionsBar else { return }

		if dropTargetsDataSource == nil, !actionsBar.isPresented {
			let targetsDataSource = OCDataSourceArray()
			targetsDataSource.setVersionedItems(targets)
			dropTargetsDataSource = targetsDataSource
			actionsBar.show(with: targetsDataSource, clientContext: ClientContext(with: clientContext, modifier: { context in
				context.dropTargetsProvider = nil
			}))
		} else if let targetsDataSource = dropTargetsDataSource {
			targetsDataSource.setVersionedItems(targets)
		}
	}
}
