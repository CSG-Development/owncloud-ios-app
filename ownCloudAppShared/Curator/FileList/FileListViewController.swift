import UIKit
import ownCloudSDK
import ownCloudApp

open class FileListViewController: UIViewController, Themeable, FileBrowserContent, SortBarDelegate, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate, DropTargetsProvider, ScrollViewProviding {

	public private(set) var clientContext: ClientContext?
	public var location: OCLocation?
	public private(set) var query: OCQuery?

	private let viewControllerUUID = UUID()
	private let queryBridge = FileListQueryBridge()
	private let zipActivity = FileListZipActivityController()
	private let multiSelect = FileListMultiSelectController()
	private let dragDrop = FileListDragDropController()
	private let actionsBar = FileListActionsBarController()

	private var shouldInvalidateActivityLayoutAfterSnapshot = false
	private var isApplyingSnapshot = false
	private var isRestoringMultiSelection = false
	private var itemLayout: ItemLayout
	private var sortDescriptor: SortDescriptor
	private var themeRegistered = false
	private var refreshControl: UIRefreshControl?
	private var contentState: FileListContentState = .loading
	private var lastAppliedContentState: FileListContentState?
	private var lastLaidOutCollectionViewSize: CGSize = .zero
	private let scrollDirectionProcessor = HCScrollDirectionProcessor()
	private var driveQuota: GAQuota?
	private var statisticsText: String?
	private var spaceHeaderTitle: String?
	private var showsSpaceHeader = false
	private var highlightItemReference: OCDataItemReference?
	private var cutStateObserver: NSObjectProtocol?

	/// Used by ClientContext permission handlers in this type.
	private var isMultiSelecting: Bool { multiSelect.isActive }

	private lazy var sortBar: SortBar = {
		let bar = SortBar(sortDescriptor: sortDescriptor)
		bar.translatesAutoresizingMaskIntoConstraints = false
		bar.delegate = self
		bar.itemLayout = itemLayout
		bar.showSelectButton = true
		bar.showsElevationShadow = false
		return bar
	}()

	private lazy var emptyOverlayView = FileListEmptyOverlayView()

	private lazy var loadingOverlayView: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .large)
		indicator.translatesAutoresizingMaskIntoConstraints = false
		indicator.hidesWhenStopped = true
		return indicator
	}()

	private lazy var collectionView: UICollectionView = {
		let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionViewLayout())
		collectionView.translatesAutoresizingMaskIntoConstraints = false
		collectionView.delegate = self
		collectionView.dragDelegate = self
		collectionView.dropDelegate = self
		collectionView.dragInteractionEnabled = true
		collectionView.backgroundColor = .clear
		collectionView.allowsSelection = true
		collectionView.allowsMultipleSelection = false
		return collectionView
	}()

	private lazy var dataSource: UICollectionViewDiffableDataSource<Int, String> = {
		let fileCellRegistration = UICollectionView.CellRegistration<FileListItemCell, String> { [weak self] cell, _, itemID in
			guard let self, let item = self.queryBridge.item(for: itemID) else { return }
			cell.configure(
				item: item,
				core: self.clientContext?.core,
				clientContext: self.clientContext,
				layout: FileListLayoutMetrics.cellLayout(for: self.itemLayout),
				showsSelection: self.multiSelect.isActive,
				isSelected: self.multiSelect.selectedItemIDs.contains(itemID)
			)
		}

		let zipCellRegistration = UICollectionView.CellRegistration<FileListZipOperationCell, String> { [weak self] cell, _, _ in
			guard let self else { return }
			self.zipActivity.configure(cell)
		}

		let spaceRegistration = UICollectionView.SupplementaryRegistration<FileListSpaceHeaderView>(elementKind: FileListSupplementaryKind.spaceHeader) { [weak self] view, _, _ in
			view.configure(title: self?.spaceHeaderTitle ?? "")
		}

		let statsRegistration = UICollectionView.SupplementaryRegistration<FileListStatisticsFooterView>(elementKind: FileListSupplementaryKind.statisticsFooter) { [weak self] view, _, _ in
			view.configure(text: self?.statisticsText)
		}

		let dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { collectionView, indexPath, itemID in
			if FileListItemID.isActivity(itemID) {
				return collectionView.dequeueConfiguredReusableCell(using: zipCellRegistration, for: indexPath, item: itemID)
			}
			return collectionView.dequeueConfiguredReusableCell(using: fileCellRegistration, for: indexPath, item: itemID)
		}
		dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
			guard indexPath.section == FileListSection.files.rawValue else { return nil }
			switch elementKind {
				case FileListSupplementaryKind.spaceHeader:
					return collectionView.dequeueConfiguredReusableSupplementary(using: spaceRegistration, for: indexPath)
				case FileListSupplementaryKind.statisticsFooter:
					return collectionView.dequeueConfiguredReusableSupplementary(using: statsRegistration, for: indexPath)
				default:
					return nil
			}
		}
		return dataSource
	}()

	public init(context inContext: ClientContext?, query inQuery: OCQuery?, location: OCLocation? = nil, highlightItemReference: OCDataItemReference? = nil) {
		inQuery?.queryResultsDataSourceIncludesStatistics = true
		self.query = inQuery
		self.location = location
		self.highlightItemReference = highlightItemReference
		self.sortDescriptor = inContext?.sortDescriptor ?? .defaultSortDescriptor
		self.itemLayout = inContext?.itemLayout ?? ItemLayoutPreference.preferred

		let vcUUID = viewControllerUUID
		let itemControllerContext = ClientContext(with: inContext, modifier: { context in
			context.add(permissionHandler: { (context, record, interaction, viewController) in
				guard let viewController = viewController as? FileListViewController, viewController.viewControllerUUID == vcUUID else {
					return true
				}

				switch interaction {
					case .selection:
						return record?.type != .drive
					case .multiselection:
						return record?.type == .item
					case .drag, .contextMenu:
						return (context?.originatingViewController as? FileListViewController)?.isMultiSelecting == false
					default:
						return true
				}
			})

			if let driveID = location?.driveID, let core = context.core {
				context.drive = core.drive(withIdentifier: driveID, attachedOnly: false)
			}
		})
		itemControllerContext.postInitializationModifier = { (owner, context) in
			if context.openItemHandler == nil {
				context.openItemHandler = owner as? OpenItemAction
			}
			if context.moreItemHandler == nil {
				context.moreItemHandler = owner as? MoreItemAction
			}
			if context.revealItemHandler == nil {
				context.revealItemHandler = owner as? RevealItemAction
			}
			if context.dropTargetsProvider == nil {
				context.dropTargetsProvider = owner as? DropTargetsProvider
			}
			context.query = (owner as? FileListViewController)?.query
			if let sortDescriptor = (owner as? FileListViewController)?.sortDescriptor {
				context.sortDescriptor = sortDescriptor
			}
			context.originatingViewController = owner as? UIViewController
		}

		self.clientContext = itemControllerContext
		super.init(nibName: nil, bundle: nil)

		itemControllerContext.postInitialize(owner: self)
		applySortDescriptor()
		configureSpaceHeader()
		configureZipActivity()
		configureQueryBridge()
		configureMultiSelect()

		scrollDirectionProcessor.onDirectionChange = { [weak self] direction in
			self?.clientContext?.browserController?.notifyScroll(direction)
		}
	}

	required public init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		queryBridge.terminate()
		zipActivity.stopObserving()
		if let cutStateObserver {
			NotificationCenter.default.removeObserver(cutStateObserver)
		}
		if themeRegistered {
			Theme.shared.unregister(client: self)
		}
	}

	// MARK: - Lifecycle

	open override func viewDidLoad() {
		super.viewDidLoad()

		cutStateObserver = NotificationCenter.default.addObserver(
			forName: CutPasteboardState.didChangeNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			guard let self else { return }
			if self.contentState == .empty {
				self.applyContentStateUI()
			}
			// Refresh + menu / folder actions so Paste appears after Cut.
			self.updateNavigationBarButtonItems()
		}

		view.addSubview(actionsBar.containerView)
		view.addSubview(sortBar)
		view.addSubview(collectionView)
		view.addSubview(emptyOverlayView)
		view.addSubview(loadingOverlayView)

		let actionsBarHeight = actionsBar.install(in: self)

		NSLayoutConstraint.activate([
			actionsBar.containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			actionsBar.containerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
			actionsBar.containerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
			actionsBarHeight,

			sortBar.topAnchor.constraint(equalTo: actionsBar.containerView.bottomAnchor),
			sortBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			sortBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			sortBar.heightAnchor.constraint(equalToConstant: FileListLayoutMetrics.sortBarHeight),

			collectionView.topAnchor.constraint(equalTo: sortBar.bottomAnchor, constant: FileListLayoutMetrics.sortBarBottomSpacing),
			collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
			collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
			collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

			emptyOverlayView.topAnchor.constraint(equalTo: sortBar.bottomAnchor, constant: FileListLayoutMetrics.sortBarBottomSpacing),
			emptyOverlayView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
			emptyOverlayView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
			emptyOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

			loadingOverlayView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
			loadingOverlayView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])

		refreshControl = UIRefreshControl(frame: .zero, primaryAction: UIAction(handler: { [weak self] _ in
			self?.performDragToRefresh()
		}))
		collectionView.refreshControl = refreshControl

		configureDragDrop()

		_ = dataSource
		queryBridge.subscribe(to: query)
		queryBridge.observe(query: query, clientContext: clientContext)
		startQueryIfNeeded()
		reloadZipOperations(applySnapshot: true)
		updateNavigationBarButtonItems()
		updateNavigationTitleFromContext()
		applyContentStateUI()
		view.backgroundColor = HCColor.Structure.appBackground(Theme.shared.activeCollection.isDark)
	}

	open override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		startQueryIfNeeded()

		let latestLayout = ItemLayoutPreference.preferred
		if latestLayout != itemLayout {
			itemLayout = latestLayout
			clientContext?.itemLayout = latestLayout
			sortBar.itemLayout = latestLayout
			reloadLayout(animated: false)
		}

		browserNavigationViewController?.updateTopAccessory()
	}

	open override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if let query {
			clientContext?.core?.stop(query)
		}
	}

	open override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
		highlightItemIfNeeded()
	}

	open override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		let size = collectionView.bounds.size
		if size.width > 1, lastLaidOutCollectionViewSize.width <= 1 {
			collectionView.collectionViewLayout.invalidateLayout()
		}
		lastLaidOutCollectionViewSize = size
	}

	private func startQueryIfNeeded() {
		guard let query, query.state == .stopped else { return }
		clientContext?.core?.start(query)
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		view.backgroundColor = HCColor.Structure.appBackground(collection.isDark)
		actionsBar.applyTheme(fillColor: collection.css.getColor(.fill, for: actionsBar.containerView))
	}

	// MARK: - Collaborator wiring

	private func configureQueryBridge() {
		queryBridge.onItemsUpdated = { [weak self] updatedItemIDs, animated in
			guard let self else { return }
			self.updateStatisticsText()
			self.applySnapshot(animated: animated, reconfigureItemIDs: updatedItemIDs)
			self.highlightItemIfNeeded()
		}
		queryBridge.onQueryRootItemChanged = { [weak self] in
			guard let self else { return }
			if self.location != nil {
				self.location = self.query?.rootItem?.location
			}
			self.updateNavigationTitleFromContext()
			self.configureSpaceHeader()
			self.updateNavigationBarButtonItems()
			self.reloadZipOperations(applySnapshot: true)
			self.recomputeContentState()
		}
		queryBridge.onNeedsContentStateRecompute = { [weak self] in
			self?.recomputeContentState()
		}
		queryBridge.onRefreshControlShouldEnd = { [weak self] in
			self?.refreshControl?.endRefreshing()
		}
	}

	private func configureMultiSelect() {
		multiSelect.onActionCompleted = { [weak self] in
			self?.setMultiSelecting(false)
		}
		multiSelect.onSelectionChanged = { [weak self] in
			guard let self else { return }
			self.updateNavigationBarButtonItems()
			self.reconfigureVisibleCells()
		}
	}

	private func configureDragDrop() {
		dragDrop.configure(
			host: self,
			actionsBar: actionsBar,
			clientContext: { [weak self] in self?.clientContext },
			isMultiSelecting: { [weak self] in self?.multiSelect.isActive ?? false },
			itemAt: { [weak self] indexPath in
				guard let self,
				      let itemID = self.dataSource.itemIdentifier(for: indexPath),
				      let item = self.queryBridge.item(for: itemID) else { return nil }
				return (itemID, item)
			}
		)
	}

	private func configureZipActivity() {
		zipActivity.onExternalChange = { [weak self] in
			self?.reloadZipOperations(applySnapshot: true)
		}
		zipActivity.onExpansionChanged = { [weak self] in
			guard let self else { return }
			self.refreshVisibleZipOperationCells(animatedExpansion: true)
			self.invalidateActivitySectionLayout(animated: true)
		}
		zipActivity.startObserving { [weak self] in
			self?.clientContext?.core?.bookmark.uuid
				?? self?.location?.bookmarkUUID
				?? self?.query?.queryLocation?.bookmarkUUID
		}
	}

	// MARK: - Snapshot

	private func applySnapshot(animated: Bool, reconfigureItemIDs: [String] = [], reloadItemIDs: [String] = []) {
		var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
		snapshot.appendSections([FileListSection.zipOperations.rawValue, FileListSection.files.rawValue])
		let activityIDs = zipActivity.activityItemIDs
		// Diffable data source requires unique identifiers. Deduplicate defensively in case
		// items briefly contains the same localID twice (seen after decompress imports).
		var seenFileIDs = Set<String>()
		let fileIDs = queryBridge.items.compactMap { item -> String? in
			let id = FileListQueryBridge.itemIdentifier(for: item)
			return seenFileIDs.insert(id).inserted ? id : nil
		}
		snapshot.appendItems(activityIDs, toSection: FileListSection.zipOperations.rawValue)
		snapshot.appendItems(fileIDs, toSection: FileListSection.files.rawValue)

		let existingIDs = Set(activityIDs).union(fileIDs)
		let idsToReload = reloadItemIDs.filter { existingIDs.contains($0) }
		if !idsToReload.isEmpty {
			snapshot.reloadItems(idsToReload)
		}
		let idsToReconfigure = reconfigureItemIDs.filter { existingIDs.contains($0) && !idsToReload.contains($0) }
		if !idsToReconfigure.isEmpty {
			snapshot.reconfigureItems(idsToReconfigure)
		}

		isApplyingSnapshot = true
		dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
			guard let self else { return }
			self.isApplyingSnapshot = false
			self.restoreMultiSelectionIfNeeded()
			// Cells animated in while isMultiSelecting changed may have been configured with
			// the wrong showsSelection value by cell registration before the toggle fired.
			// Reconfigure now so every visible cell reflects the current select-mode state.
			self.reconfigureVisibleCells()
			self.refreshVisibleZipOperationCells()
			if self.shouldInvalidateActivityLayoutAfterSnapshot {
				self.shouldInvalidateActivityLayoutAfterSnapshot = false
				self.invalidateActivitySectionLayout(animated: self.zipActivity.hasOperations && self.zipActivity.isExpanded)
			}
		}
	}

	private func restoreMultiSelectionIfNeeded() {
		isRestoringMultiSelection = true
		defer { isRestoringMultiSelection = false }
		multiSelect.restoreSelectionIfNeeded(in: collectionView) { [weak self] itemID in
			self?.dataSource.indexPath(for: itemID)
		}
	}

	// MARK: - Zip activity

	private func reloadZipOperations(applySnapshot shouldApply: Bool) {
		let membershipChanged = zipActivity.reload()

		if shouldApply {
			if membershipChanged {
				// Membership changed — rebuild sections. Progress-only updates skip this path.
				shouldInvalidateActivityLayoutAfterSnapshot = true
				applySnapshot(animated: false)
			} else {
				refreshVisibleZipOperationCells()
			}
			// Avoid recomputing content/nav on every progress tick — that recreates the + menu and dismisses it.
			if membershipChanged || contentState == .empty || contentState == .loading {
				recomputeContentState()
			}
		} else {
			refreshVisibleZipOperationCells()
		}
	}

	private func refreshVisibleZipOperationCells(animatedExpansion: Bool = false) {
		guard collectionView.numberOfSections > FileListSection.zipOperations.rawValue,
		      collectionView.numberOfItems(inSection: FileListSection.zipOperations.rawValue) > 0 else {
			return
		}
		let indexPath = IndexPath(item: 0, section: FileListSection.zipOperations.rawValue)
		guard let cell = collectionView.cellForItem(at: indexPath) as? FileListZipOperationCell else {
			return
		}
		zipActivity.configure(cell, animatedExpansion: animatedExpansion)
	}

	private func invalidateActivitySectionLayout(animated: Bool) {
		collectionView.collectionViewLayout.invalidateLayout()
		guard animated else {
			UIView.performWithoutAnimation {
				self.collectionView.layoutIfNeeded()
			}
			return
		}
		UIView.animate(
			withDuration: 0.28,
			delay: 0,
			options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]
		) {
			self.collectionView.layoutIfNeeded()
		}
	}

	// MARK: - Content state

	private func recomputeContentState() {
		guard let dataSource = query?.queryResultsDataSource else {
			contentState = queryBridge.items.isEmpty ? .loading : .hasContent
			applyContentStateUI()
			return
		}

		switch dataSource.state {
			case .loading:
				contentState = zipActivity.hasOperations ? .hasContent : .loading
			case .idle:
				if query?.state == .targetRemoved {
					contentState = .removed
				} else if !queryBridge.items.isEmpty || zipActivity.hasOperations {
					contentState = .hasContent
				} else if isQueryStillLoading {
					contentState = .loading
				} else if query?.rootItem == nil, query?.isCustom != true {
					contentState = .loading
				} else {
					contentState = .empty
				}
			default:
				break
		}
		applyContentStateUI()
	}

	/// Stopped/started queries have not produced a final empty listing yet.
	private var isQueryStillLoading: Bool {
		switch query?.state {
			case .stopped, .started:
				return true
			case .waitingForServerReply:
				return clientContext?.core?.connectionStatus == .online
			default:
				return false
		}
	}

	private func applyContentStateUI() {
		let contentStateChanged = lastAppliedContentState != contentState
		lastAppliedContentState = contentState

		switch contentState {
			case .loading:
				sortBar.isHidden = true
				emptyOverlayView.isHidden = true
				loadingOverlayView.startAnimating()
				collectionView.isHidden = false
			case .empty:
				sortBar.isHidden = true
				emptyOverlayView.isHidden = false
				loadingOverlayView.stopAnimating()
				emptyOverlayView.configure(
					title: OCLocalizedString("No contents", nil),
					message: OCLocalizedString("This folder has no contents.", nil),
					actions: emptyOverlayActions()
				)
				collectionView.isHidden = false
			case .removed:
				sortBar.isHidden = true
				emptyOverlayView.isHidden = false
				loadingOverlayView.stopAnimating()
				emptyOverlayView.configure(
					title: OCLocalizedString("Folder removed", nil),
					message: OCLocalizedString("This folder is no longer available.", nil)
				)
				collectionView.isHidden = true
			case .hasContent:
				sortBar.isHidden = false
				emptyOverlayView.isHidden = true
				loadingOverlayView.stopAnimating()
				collectionView.isHidden = false
		}
		// Recreating the + UIBarButtonItem dismisses an open menu — only do it when state changes.
		if contentStateChanged {
			updateNavigationBarButtonItems()
			clientContext?.browserController?.applyScrollabilityCheckForCurrentContent()
		}
	}

	private func performDragToRefresh() {
		guard let core = clientContext?.core, let query else {
			refreshControl?.endRefreshing()
			return
		}
		core.reload(query)
	}

	// MARK: - Layout

	private func makeCollectionViewLayout() -> UICollectionViewLayout {
		FileListLayoutMetrics.makeCompositionalLayout { [weak self] in
			guard let self else {
				return .init(itemLayout: .list, showsSpaceHeader: false, showsStatisticsFooter: false, activitySectionHeight: nil, swipeActionsProvider: nil)
			}
			return .init(
				itemLayout: self.itemLayout,
				showsSpaceHeader: self.showsSpaceHeader,
				showsStatisticsFooter: self.statisticsText != nil && self.contentState == .hasContent,
				activitySectionHeight: self.zipActivity.hasOperations ? self.zipActivity.preferredHeight() : nil,
				swipeActionsProvider: { [weak self] indexPath in
					self?.swipeActions(for: indexPath)
				}
			)
		}
	}

	private func reloadLayout(animated: Bool) {
		let layout = makeCollectionViewLayout()
		collectionView.setCollectionViewLayout(layout, animated: animated)
		reconfigureVisibleCells()
	}

	private func reconfigureVisibleCells() {
		let cellLayout = FileListLayoutMetrics.cellLayout(for: itemLayout)
		for indexPath in collectionView.indexPathsForVisibleItems {
			guard let itemID = dataSource.itemIdentifier(for: indexPath) else { continue }

			if FileListItemID.isActivity(itemID),
			   let cell = collectionView.cellForItem(at: indexPath) as? FileListZipOperationCell {
				zipActivity.configure(cell)
				continue
			}

			guard let item = queryBridge.item(for: itemID),
			      let cell = collectionView.cellForItem(at: indexPath) as? FileListItemCell else {
				continue
			}

			cell.configure(
				item: item,
				core: clientContext?.core,
				clientContext: clientContext,
				layout: cellLayout,
				showsSelection: multiSelect.isActive,
				isSelected: multiSelect.selectedItemIDs.contains(itemID)
			)
		}
	}

	// MARK: - Space header / statistics

	private func configureSpaceHeader() {
		showsSpaceHeader = false
		spaceHeaderTitle = nil

		guard let core = clientContext?.core, core.useDrives,
		      let drive = clientContext?.drive,
		      drive.specialType == .space,
		      query?.queryLocation?.isRoot == true else {
			driveQuota = clientContext?.drive?.quota
			updateStatisticsText()
			return
		}

		showsSpaceHeader = true
		spaceHeaderTitle = drive.name ?? OCLocalizedString("Space", nil)
		driveQuota = drive.quota
		updateStatisticsText()
	}

	private func updateStatisticsText() {
		var folderStatisticsText = ""
		var quotaInfoText = ""

		if let folderStatistics = queryBridge.folderStatistics {
			folderStatisticsText = OCLocalizedFormat("{{itemCount}} items with {{totalSize}} total ({{fileCount}} files, {{folderCount}} folders)", [
				"itemCount": NumberFormatter.localizedString(from: NSNumber(value: folderStatistics.itemCount?.intValue ?? 0), number: .decimal),
				"fileCount": NumberFormatter.localizedString(from: NSNumber(value: folderStatistics.fileCount?.intValue ?? 0), number: .decimal),
				"folderCount": NumberFormatter.localizedString(from: NSNumber(value: folderStatistics.folderCount?.intValue ?? 0), number: .decimal),
				"totalSize": folderStatistics.localizedSize ?? "-"
			])
		}

		if let driveQuota, let remainingBytes = driveQuota.remaining {
			quotaInfoText = OCLocalizedFormat("{{remaining}} available", [
				"remaining": ByteCountFormatter.string(fromByteCount: remainingBytes.int64Value, countStyle: .file)
			])
			if folderStatisticsText.count > 0 {
				folderStatisticsText += "\n" + quotaInfoText
			} else {
				folderStatisticsText = quotaInfoText
			}
		}

		statisticsText = folderStatisticsText.isEmpty ? nil : folderStatisticsText
	}

	// MARK: - Navigation

	private func updateNavigationBarButtonItems() {
		var viewActionButtons: [UIBarButtonItem] = []

		if contentState != .removed, query?.queryLocation != nil {
			if clientContext?.moreItemHandler != nil, clientContext?.hasPermission(for: .moreOptions) == true {
				let folderActionBarButton = UIBarButtonItem(image: UIImage(named: "more-dots"), style: .plain, target: self, action: #selector(moreBarButtonPressed))
				folderActionBarButton.accessibilityIdentifier = "client.folder-action"
				folderActionBarButton.accessibilityLabel = OCLocalizedString("Actions", nil)
				viewActionButtons.append(folderActionBarButton)
			}

			if clientContext?.hasPermission(for: .addContent) == true {
				let plusBarButton = UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil)
				plusBarButton.menu = UIMenu(title: "", children: [
					UIDeferredMenuElement.uncached({ [weak self] completion in
						guard let self, let rootItem = self.query?.rootItem, let clientContext = self.clientContext else {
							completion([])
							return
						}
						let contextMenuProvider = rootItem as DataItemContextMenuInteraction
						if let contextMenuElements = contextMenuProvider.composeContextMenuItems(in: self, location: .folderAction, with: clientContext) {
							completion(contextMenuElements.isEmpty
								? [UIAction(title: OCLocalizedString("No actions available", nil), attributes: .disabled, handler: { _ in })]
								: contextMenuElements)
						} else {
							completion([])
						}
					})
				])
				plusBarButton.accessibilityIdentifier = "client.file-add"
				plusBarButton.accessibilityLabel = OCLocalizedString("Add item", nil)
				viewActionButtons.append(plusBarButton)
			}
		}

		if multiSelect.isActive {
			let toggleTitle = multiSelect.selectedItemIDs.count == queryBridge.items.count && !queryBridge.items.isEmpty
				? OCLocalizedString("Deselect All", nil)
				: OCLocalizedString("Select All", nil)
			let toggleItem = UIBarButtonItem(title: toggleTitle, primaryAction: UIAction(handler: { [weak self] _ in
				self?.selectDeselectAll()
			}))
			navigationItem.navigationContent.add(items: [
				NavigationContentItem(identifier: "multiselect-toggle", area: .left, priority: .high, position: .trailing, items: [toggleItem])
			])
		} else {
			navigationItem.navigationContent.remove(itemsWithIdentifier: "multiselect-toggle")
		}

		navigationItem.navigationContent.add(items: [
			NavigationContentItem(identifier: "client-actions-right", area: .right, priority: .standard, position: .trailing, items: viewActionButtons)
		])
	}

	@objc private func moreBarButtonPressed(_ sender: UIBarButtonItem) {
		guard let rootItem = query?.rootItem, let clientContext, let moreItemHandler = clientContext.moreItemHandler else {
			return
		}
		moreItemHandler.moreOptions(for: rootItem, at: .moreFolder, context: clientContext, sender: sender)
	}

	private func emptyOverlayActions() -> [(title: String, handler: () -> Void)] {
		guard let context = clientContext,
		      let core = context.core,
		      let item = query?.rootItem ?? (context.rootItem as? OCItem),
		      context.hasPermission(for: .addContent) == true else {
			return []
		}

		let originatingViewController: UIViewController = context.originatingViewController ?? self
		let actionsLocation = OCExtensionLocation(ofType: .action, identifier: .emptyFolder)
		let actionContext = ActionContext(viewController: originatingViewController, clientContext: context, core: core, query: query, items: [item], location: actionsLocation, sender: self)
		let emptyFolderActions = Action.sortedApplicableActions(for: actionContext)

		return emptyFolderActions.map { action in
			(title: action.actionExtension.name, handler: {
				action.perform()
			})
		}
	}

	private func updateNavigationTitleFromContext() {
		var navigationTitle: String?
		var navigationLocation: OCLocation?

		if let location {
			navigationTitle = location.displayName(in: clientContext)
			navigationLocation = location
		}
		if navigationTitle == nil, let queryLocation = query?.queryLocation {
			navigationTitle = queryLocation.displayName(in: clientContext)
			navigationLocation = queryLocation
		}
		if navigationTitle == nil, let queryRootItem = clientContext?.rootItem as? OCItem {
			navigationTitle = queryRootItem.name
			navigationLocation = queryRootItem.location
		}

		if let navigationLocation, !navigationLocation.isRoot, let clientContext {
			let navigationTitleLabel = ThemeCSSLabel(withSelectors: [.title])
			navigationTitleLabel.font = UIFont.systemFont(ofSize: UIFont.buttonFontSize, weight: .semibold)
			navigationTitleLabel.lineBreakMode = .byTruncatingMiddle
			navigationTitleLabel.text = navigationLocation.displayName(in: clientContext)
			navigationItem.navigationContent.add(items: [
				NavigationContentItem(identifier: "navigation-location", area: .title, priority: .standard, position: .middle, titleView: navigationTitleLabel)
			])
		} else {
			navigationItem.navigationContent.remove(itemsWithIdentifier: "navigation-location")
			if let navigationTitle {
				let title = OCLocation.navigationTitleReplacingAccountName(navigationTitle, in: clientContext) ?? navigationTitle
				navigationItem.titleLabelText = title.redacted()
				navigationItem.title = title.redacted()
			}
		}
	}

	// MARK: - Sorting

	public func sortBar(_ sortBar: SortBar, didChangeSortDescriptor newSortDescriptor: SortDescriptor) {
		sortDescriptor = newSortDescriptor
		clientContext?.sortDescriptor = newSortDescriptor
		SortDescriptor.defaultSortDescriptor = newSortDescriptor
		queryBridge.suppressNextSnapshotAnimation = true
		applySortDescriptor()
	}

	private func applySortDescriptor() {
		query?.sortComparator = sortDescriptor.comparator
	}

	public func sortBar(_ sortBar: SortBar, itemLayout: ItemLayout) {
		guard itemLayout != self.itemLayout else { return }
		self.itemLayout = itemLayout
		clientContext?.itemLayout = itemLayout
		var ancestorContext = clientContext
		while let parent = ancestorContext?.parent {
			parent.itemLayout = itemLayout
			ancestorContext = parent
		}
		reloadLayout(animated: false)
	}

	public func sortBarToggleSelectMode(_ sortBar: SortBar) {
		guard clientContext?.hasPermission(for: .multiselection) == true else { return }
		setMultiSelecting(!multiSelect.isActive)
	}

	// MARK: - Multi-select

	private func setMultiSelecting(_ selecting: Bool) {
		dragDrop.clearDropTargetsSideState()
		sortBar.multiselectActive = selecting
		multiSelect.setActive(
			selecting,
			host: self,
			clientContext: clientContext,
			query: query,
			items: queryBridge.items,
			actionsBar: actionsBar,
			collectionView: collectionView,
			itemIdentifier: FileListQueryBridge.itemIdentifier
		) { [weak self] fileIDs in
			guard let self else { return }
			self.updateNavigationBarButtonItems()
			if fileIDs.isEmpty {
				self.reconfigureVisibleCells()
			} else {
				self.applySnapshot(animated: false, reconfigureItemIDs: fileIDs)
			}
		}
	}

	private func selectDeselectAll() {
		multiSelect.selectDeselectAll(
			items: queryBridge.items,
			itemIdentifier: FileListQueryBridge.itemIdentifier,
			collectionView: collectionView
		)
	}

	// MARK: - Selection / open

	public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		guard let itemID = dataSource.itemIdentifier(for: indexPath) else { return false }
		return !FileListItemID.isActivity(itemID)
	}

	public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard let itemID = dataSource.itemIdentifier(for: indexPath),
		      !FileListItemID.isActivity(itemID),
		      let item = queryBridge.item(for: itemID) else { return }

		if multiSelect.isActive {
			multiSelect.select(itemID: itemID, item: item, restoring: isRestoringMultiSelection)
			return
		}

		collectionView.deselectItem(at: indexPath, animated: true)
		_ = (item as DataItemSelectionInteraction).openItem?(from: self, with: clientContext, animated: true, pushViewController: true, completion: nil)
	}

	public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
		guard multiSelect.isActive,
		      !isApplyingSnapshot,
		      !isRestoringMultiSelection,
		      let itemID = dataSource.itemIdentifier(for: indexPath),
		      !FileListItemID.isActivity(itemID),
		      let item = queryBridge.item(for: itemID) else { return }
		multiSelect.deselect(itemID: itemID, item: item)
	}

	public func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
		guard !multiSelect.isActive,
		      let itemID = dataSource.itemIdentifier(for: indexPath),
		      !FileListItemID.isActivity(itemID),
		      let item = queryBridge.item(for: itemID),
		      let clientContext else { return nil }

		if let contextMenuProvider = clientContext.contextMenuProvider {
			return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { [weak self] _ in
				guard let self,
				      let menuItems = contextMenuProvider.composeContextMenuElements(for: self, item: item, location: .contextMenuItem, context: clientContext, sender: nil) else {
					return nil
				}
				return UIMenu(title: "", children: menuItems)
			})
		}

		if let contextMenuInteraction = item as? DataItemContextMenuInteraction {
			return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { [weak self] _ in
				guard let self,
				      let menuItems = contextMenuInteraction.composeContextMenuItems(in: self, location: .contextMenuItem, with: clientContext) else {
					return nil
				}
				return UIMenu(title: "", children: menuItems)
			})
		}

		return nil
	}

	private func swipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		guard !multiSelect.isActive,
		      let itemID = dataSource.itemIdentifier(for: indexPath),
		      !FileListItemID.isActivity(itemID),
		      let item = queryBridge.item(for: itemID) as? DataItemSwipeInteraction else { return nil }
		return item.provideTrailingSwipeActions?(with: clientContext)
	}

	// MARK: - Drag & drop

	public func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		dragDrop.dragItems(at: indexPath)
	}

	public func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
		dragDrop.canHandle(session)
	}

	public func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		dragDrop.dropProposal(for: session, destinationIndexPath: destinationIndexPath)
	}

	public func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
		dragDrop.performDrop(with: coordinator, collectionView: collectionView)
	}

	public func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
		dragDrop.dropSessionDidEnd(session)
	}

	public func canProvideDropTargets(for dropSession: UIDropSession, target: UIView) -> Bool {
		dragDrop.canProvideDropTargets(for: dropSession)
	}

	public func provideDropTargets(for dropSession: UIDropSession, target view: UIView) -> [OCDataItem & OCDataItemVersioning]? {
		dragDrop.provideDropTargets(for: dropSession)
	}

	public func cleanupDropTargets(for dropSession: UIDropSession, target view: UIView) {
		dragDrop.cleanupDropTargets(for: dropSession)
	}

	// MARK: - Highlight

	public func highlightItem(withReference reference: OCDataItemReference) {
		highlightItemReference = reference
		highlightItemIfNeeded()
	}

	private func highlightItemIfNeeded() {
		guard let highlightItemReference else { return }
		guard let match = queryBridge.items.first(where: { ($0.dataItemReference as NSObject).isEqual(highlightItemReference as NSObject) }) else { return }

		let id = FileListQueryBridge.itemIdentifier(for: match)
		guard let indexPath = dataSource.indexPath(for: id) else { return }

		collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
		collectionView.selectItem(at: indexPath, animated: true, scrollPosition: [])
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			self?.collectionView.deselectItem(at: indexPath, animated: true)
		}
		self.highlightItemReference = nil
	}

	// MARK: - Scroll / landscape chrome

	public func scrollViewDidScroll(_ scrollView: UIScrollView) {
		guard presentedViewController == nil else { return }
		guard scrollView.isDragging || scrollView.isDecelerating else { return }
		scrollDirectionProcessor.scrollViewDidScroll(scrollView)
	}

	public var providedScrollView: UIScrollView? {
		collectionView.isHidden ? nil : collectionView
	}

	public var allowsLandscapeChromeAutoHide: Bool {
		contentState == .hasContent
	}
}

extension ClientItemViewController: FileBrowserContent {}
