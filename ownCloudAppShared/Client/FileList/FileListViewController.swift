//
//  FileListViewController.swift
//  ownCloudAppShared
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2026, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 */

import UIKit
import ownCloudSDK
import ownCloudApp

private enum FileListSupplementaryKind {
	static let spaceHeader = "file-list-space-header"
	static let statisticsFooter = "file-list-statistics-footer"
}

private enum FileListContentState {
	case loading
	case empty
	case removed
	case hasContent
}

private final class FileListSpaceHeaderView: UICollectionReusableView, Themeable {
	private let titleLabel = UILabel()
	private var themeRegistered = false

	override init(frame: CGRect) {
		super.init(frame: frame)
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
		titleLabel.numberOfLines = 1
		titleLabel.lineBreakMode = .byTruncatingTail
		addSubview(titleLabel)
		NSLayoutConstraint.activate([
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(title: String) {
		titleLabel.text = title
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil, !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		titleLabel.textColor = HCColor.Content.textPrimary(collection.isDark)
		backgroundColor = .clear
	}
}

private final class FileListStatisticsFooterView: UICollectionReusableView, Themeable {
	private let label = UILabel()
	private var themeRegistered = false

	override init(frame: CGRect) {
		super.init(frame: frame)
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .footnote)
		label.textAlignment = .center
		label.numberOfLines = 0
		addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(text: String?) {
		label.text = text
		isHidden = (text == nil || text?.isEmpty == true)
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil, !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		label.textColor = HCColor.Content.textSecondary(collection.isDark)
		backgroundColor = .clear
	}
}

open class FileListViewController: UIViewController, Themeable, FileBrowserContent, SortBarDelegate, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate, DropTargetsProvider {

	public private(set) var clientContext: ClientContext?
	public var location: OCLocation?
	public private(set) var query: OCQuery?

	private let viewControllerUUID = UUID()
	private var items: [OCItem] = []
	private var itemsByID: [String: OCItem] = [:]
	private var selectedItemIDs = Set<String>()
	private var isMultiSelecting = false
	private var itemLayout: ItemLayout
	private var sortDescriptor: SortDescriptor
	private var themeRegistered = false
	private var refreshControl: UIRefreshControl?
	private var dataSourceSubscription: OCDataSourceSubscription?
	private var queryStateObservation: NSKeyValueObservation?
	private var queryRootItemObservation: NSKeyValueObservation?
	private var coreConnectionStatusObservation: NSKeyValueObservation?
	private var contentState: FileListContentState = .loading
	private var folderStatistics: OCStatistic?
	private var driveQuota: GAQuota?
	private var statisticsText: String?
	private var spaceHeaderTitle: String?
	private var showsSpaceHeader = false
	private var multiSelectionActionContext: ActionContext?
	private var highlightItemReference: OCDataItemReference?
	private var dropTargetsActionContext: ActionContext?
	private var lastDropProposalDestinationIndexPath: IndexPath?

	private lazy var sortBar: SortBar = {
		let bar = SortBar(sortDescriptor: sortDescriptor)
		bar.translatesAutoresizingMaskIntoConstraints = false
		bar.delegate = self
		bar.itemLayout = itemLayout
		bar.showSelectButton = true
		return bar
	}()

	private lazy var emptyOverlayView: UIView = {
		let container = UIView()
		container.translatesAutoresizingMaskIntoConstraints = false
		container.isHidden = true

		let stack = UIStackView(arrangedSubviews: [emptyIconView, emptyTitleLabel, emptyMessageLabel])
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 8
		container.addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
			stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
			stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
		])
		return container
	}()

	private lazy var emptyIconView: UIImageView = {
		let imageView = UIImageView(image: OCSymbol.icon(forSymbolName: "folder"))
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.contentMode = .scaleAspectFit
		NSLayoutConstraint.activate([
			imageView.widthAnchor.constraint(equalToConstant: 64),
			imageView.heightAnchor.constraint(equalToConstant: 48)
		])
		return imageView
	}()

	private lazy var emptyTitleLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .headline)
		label.textAlignment = .center
		label.numberOfLines = 0
		label.text = OCLocalizedString("No contents", nil)
		return label
	}()

	private lazy var emptyMessageLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .subheadline)
		label.textAlignment = .center
		label.numberOfLines = 0
		label.text = OCLocalizedString("This folder has no contents.", nil)
		return label
	}()

	private lazy var loadingOverlayView: UIActivityIndicatorView = {
		let indicator = UIActivityIndicatorView(style: .large)
		indicator.translatesAutoresizingMaskIntoConstraints = false
		indicator.hidesWhenStopped = true
		return indicator
	}()

	private lazy var multiSelectActionBar: UIScrollView = {
		let scrollView = UIScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.showsHorizontalScrollIndicator = false
		scrollView.isHidden = true
		scrollView.addSubview(multiSelectActionStack)
		NSLayoutConstraint.activate([
			multiSelectActionStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
			multiSelectActionStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
			multiSelectActionStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
			multiSelectActionStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
			multiSelectActionStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -24)
		])
		return scrollView
	}()

	private lazy var multiSelectActionStack: UIStackView = {
		let stack = UIStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .horizontal
		stack.spacing = 12
		stack.alignment = .center
		return stack
	}()

	private var multiSelectActionBarHeightConstraint: NSLayoutConstraint?

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
		let cellRegistration = UICollectionView.CellRegistration<FileListItemCell, String> { [weak self] cell, _, itemID in
			guard let self, let item = self.itemsByID[itemID] else { return }
			cell.configure(
				item: item,
				core: self.clientContext?.core,
				layout: self.itemLayout == .list ? .list : .grid,
				showsSelection: self.isMultiSelecting,
				isSelected: self.selectedItemIDs.contains(itemID)
			)
		}

		let spaceRegistration = UICollectionView.SupplementaryRegistration<FileListSpaceHeaderView>(elementKind: FileListSupplementaryKind.spaceHeader) { [weak self] view, _, _ in
			view.configure(title: self?.spaceHeaderTitle ?? "")
		}

		let statsRegistration = UICollectionView.SupplementaryRegistration<FileListStatisticsFooterView>(elementKind: FileListSupplementaryKind.statisticsFooter) { [weak self] view, _, _ in
			view.configure(text: self?.statisticsText)
		}

		let dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { collectionView, indexPath, itemID in
			collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemID)
		}
		dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
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
	}

	required public init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		dataSourceSubscription?.terminate()
		queryStateObservation?.invalidate()
		queryRootItemObservation?.invalidate()
		coreConnectionStatusObservation?.invalidate()
		if themeRegistered {
			Theme.shared.unregister(client: self)
		}
	}

	// MARK: - Lifecycle

	open override func viewDidLoad() {
		super.viewDidLoad()

		view.addSubview(sortBar)
		view.addSubview(collectionView)
		view.addSubview(emptyOverlayView)
		view.addSubview(loadingOverlayView)
		view.addSubview(multiSelectActionBar)

		let actionBarHeight = multiSelectActionBar.heightAnchor.constraint(equalToConstant: 0)
		multiSelectActionBarHeightConstraint = actionBarHeight

		NSLayoutConstraint.activate([
			sortBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			sortBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			sortBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			sortBar.heightAnchor.constraint(equalToConstant: FileListLayoutMetrics.sortBarHeight),

			collectionView.topAnchor.constraint(equalTo: sortBar.bottomAnchor),
			collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			collectionView.bottomAnchor.constraint(equalTo: multiSelectActionBar.topAnchor),

			multiSelectActionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			multiSelectActionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			multiSelectActionBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			actionBarHeight,

			emptyOverlayView.topAnchor.constraint(equalTo: sortBar.bottomAnchor),
			emptyOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			emptyOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			emptyOverlayView.bottomAnchor.constraint(equalTo: multiSelectActionBar.topAnchor),

			loadingOverlayView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			loadingOverlayView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])

		refreshControl = UIRefreshControl(frame: .zero, primaryAction: UIAction(handler: { [weak self] _ in
			self?.performDragToRefresh()
		}))
		collectionView.refreshControl = refreshControl

		_ = dataSource
		subscribeToQueryDataSource()
		observeQueryState()
		updateNavigationBarButtonItems()
		updateNavigationTitleFromContext()
		applyContentStateUI()
	}

	open override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if let query {
			clientContext?.core?.start(query)
		}

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

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		view.backgroundColor = .systemBackground
		emptyTitleLabel.textColor = HCColor.Content.textPrimary(collection.isDark)
		emptyMessageLabel.textColor = HCColor.Content.textSecondary(collection.isDark)
		multiSelectActionBar.backgroundColor = .secondarySystemBackground
	}

	// MARK: - Query bridge

	private func subscribeToQueryDataSource() {
		guard let dataSource = query?.queryResultsDataSource else { return }

		dataSourceSubscription?.terminate()
		dataSourceSubscription = dataSource.subscribe(updateHandler: { [weak self] subscription in
			self?.handleDataSourceUpdate(from: subscription)
		}, on: .main, trackDifferences: true, performInitialUpdate: true)
	}

	private func observeQueryState() {
		queryStateObservation = query?.observe(\OCQuery.state, options: []) { [weak self] query, _ in
			OnMainThread {
				if query.state == .idle || self?.clientContext?.core?.connectionStatus != .online {
					self?.refreshControl?.endRefreshing()
				}
				self?.recomputeContentState()
			}
		}

		queryRootItemObservation = query?.observe(\OCQuery.rootItem, options: []) { [weak self] query, _ in
			OnMainThread {
				self?.clientContext?.rootItem = query.rootItem
				if self?.location != nil {
					self?.location = query.rootItem?.location
				}
				self?.updateNavigationTitleFromContext()
				self?.configureSpaceHeader()
				self?.updateNavigationBarButtonItems()
				self?.recomputeContentState()
			}
		}

		coreConnectionStatusObservation = clientContext?.core?.observe(\OCCore.connectionStatus, options: []) { [weak self] _, _ in
			OnMainThread {
				self?.recomputeContentState()
			}
		}
	}

	private func handleDataSourceUpdate(from subscription: OCDataSourceSubscription) {
		let snapshot = subscription.snapshotResettingChangeTracking(true)
		var nextItems: [OCItem] = []
		var nextByID: [String: OCItem] = [:]

		for itemRef in snapshot.items {
			guard let record = try? subscription.source?.record(forItemRef: itemRef),
			      let item = record.item as? OCItem else { continue }
			let id = itemIdentifier(for: item)
			nextItems.append(item)
			nextByID[id] = item
		}

		items = nextItems
		itemsByID = nextByID
		folderStatistics = snapshot.specialItems?[.folderStatistics] as? OCStatistic
		updateStatisticsText()
		applySnapshot(animated: true)
		recomputeContentState()
		highlightItemIfNeeded()
	}

	private func itemIdentifier(for item: OCItem) -> String {
		if let localID = item.localID as String? {
			return localID
		}
		if let fileID = item.fileID {
			return fileID
		}
		return item.path ?? item.name ?? UUID().uuidString
	}

	private func applySnapshot(animated: Bool) {
		var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
		snapshot.appendSections([0])
		snapshot.appendItems(items.map { itemIdentifier(for: $0) }, toSection: 0)
		dataSource.apply(snapshot, animatingDifferences: animated)
	}

	private func recomputeContentState() {
		guard let dataSource = query?.queryResultsDataSource else {
			contentState = items.isEmpty ? .loading : .hasContent
			applyContentStateUI()
			return
		}

		switch dataSource.state {
			case .loading:
				contentState = .loading
			case .idle:
				if query?.state == .targetRemoved {
					contentState = .removed
				} else if !items.isEmpty {
					contentState = .hasContent
				} else if query?.state == .started || query?.state == .waitingForServerReply,
				          clientContext?.core?.connectionStatus == .online {
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

	private func applyContentStateUI() {
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
				emptyTitleLabel.text = OCLocalizedString("No contents", nil)
				emptyMessageLabel.text = OCLocalizedString("This folder has no contents.", nil)
				collectionView.isHidden = true
			case .removed:
				sortBar.isHidden = true
				emptyOverlayView.isHidden = false
				loadingOverlayView.stopAnimating()
				emptyTitleLabel.text = OCLocalizedString("Folder removed", nil)
				emptyMessageLabel.text = OCLocalizedString("This folder is no longer available.", nil)
				collectionView.isHidden = true
			case .hasContent:
				sortBar.isHidden = false
				emptyOverlayView.isHidden = true
				loadingOverlayView.stopAnimating()
				collectionView.isHidden = false
		}
		updateNavigationBarButtonItems()
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
		UICollectionViewCompositionalLayout { [weak self] _, environment in
			guard let self else { return nil }

			let section: NSCollectionLayoutSection
			if self.itemLayout == .list {
				var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
				listConfig.backgroundColor = .clear
				listConfig.showsSeparators = true
				if self.showsSpaceHeader {
					listConfig.headerMode = .supplementary
				}
				if self.statisticsText != nil, self.contentState == .hasContent {
					listConfig.footerMode = .supplementary
				}
				listConfig.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
					self?.swipeActions(for: indexPath)
				}
				section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
			} else {
				section = FileListLayoutMetrics.makeGridSection(layoutEnvironment: environment)
				var boundaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
				if self.showsSpaceHeader {
					let header = NSCollectionLayoutBoundarySupplementaryItem(
						layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(FileListLayoutMetrics.spaceHeaderHeight)),
						elementKind: FileListSupplementaryKind.spaceHeader,
						alignment: .top
					)
					boundaryItems.append(header)
				}
				if self.statisticsText != nil, self.contentState == .hasContent {
					let footer = NSCollectionLayoutBoundarySupplementaryItem(
						layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(FileListLayoutMetrics.statisticsFooterHeight)),
						elementKind: FileListSupplementaryKind.statisticsFooter,
						alignment: .bottom
					)
					boundaryItems.append(footer)
				}
				section.boundarySupplementaryItems = boundaryItems
			}

			if self.itemLayout == .list {
				var boundaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
				if self.showsSpaceHeader {
					let header = NSCollectionLayoutBoundarySupplementaryItem(
						layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(FileListLayoutMetrics.spaceHeaderHeight)),
						elementKind: FileListSupplementaryKind.spaceHeader,
						alignment: .top
					)
					boundaryItems.append(header)
				}
				if self.statisticsText != nil, self.contentState == .hasContent {
					let footer = NSCollectionLayoutBoundarySupplementaryItem(
						layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(FileListLayoutMetrics.statisticsFooterHeight)),
						elementKind: FileListSupplementaryKind.statisticsFooter,
						alignment: .bottom
					)
					boundaryItems.append(footer)
				}
				if !boundaryItems.isEmpty {
					section.boundarySupplementaryItems = boundaryItems
				}
			}

			return section
		}
	}

	private func reloadLayout(animated: Bool) {
		let layout = makeCollectionViewLayout()
		collectionView.setCollectionViewLayout(layout, animated: animated)
		reconfigureVisibleCells()
	}

	private func reconfigureVisibleCells() {
		var snapshot = dataSource.snapshot()
		let ids = snapshot.itemIdentifiers
		guard !ids.isEmpty else { return }
		snapshot.reconfigureItems(ids)
		dataSource.apply(snapshot, animatingDifferences: false)
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

		if let folderStatistics {
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

		if isMultiSelecting {
			let toggleTitle = selectedItemIDs.count == items.count && !items.isEmpty
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
		reloadLayout(animated: true)
	}

	public func sortBarToggleSelectMode(_ sortBar: SortBar) {
		guard clientContext?.hasPermission(for: .multiselection) == true else { return }
		setMultiSelecting(!isMultiSelecting)
	}

	// MARK: - Multi-select

	private func setMultiSelecting(_ selecting: Bool) {
		guard selecting != isMultiSelecting else { return }
		isMultiSelecting = selecting
		sortBar.multiselectActive = selecting
		collectionView.allowsMultipleSelection = selecting
		selectedItemIDs.removeAll()
		collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false) }

		if selecting {
			if let core = clientContext?.core {
				let actionsLocation = OCExtensionLocation(ofType: .action, identifier: .multiSelection)
				multiSelectionActionContext = ActionContext(viewController: self, clientContext: clientContext, core: core, query: query, items: [], location: actionsLocation)
			}
			showMultiSelectActionBar(true)
			refreshMultiselectActions()
		} else {
			multiSelectionActionContext = nil
			showMultiSelectActionBar(false)
		}

		updateNavigationBarButtonItems()
		reconfigureVisibleCells()
	}

	private func showMultiSelectActionBar(_ show: Bool) {
		multiSelectActionBar.isHidden = !show
		multiSelectActionBarHeightConstraint?.constant = show ? 72 : 0
		UIView.animate(withDuration: 0.2) {
			self.view.layoutIfNeeded()
		}
	}

	private func refreshMultiselectActions() {
		multiSelectActionStack.arrangedSubviews.forEach {
			multiSelectActionStack.removeArrangedSubview($0)
			$0.removeFromSuperview()
		}

		guard let multiSelectionActionContext else { return }

		if multiSelectionActionContext.items.isEmpty {
			let label = UILabel()
			label.text = OCLocalizedString("Select one or more items.", nil)
			label.font = UIFont.preferredFont(forTextStyle: .footnote)
			label.textColor = .secondaryLabel
			multiSelectActionStack.addArrangedSubview(label)
			return
		}

		let actions = Action.sortedApplicableActions(for: multiSelectionActionContext)
		for action in actions {
			action.completionHandler = { [weak self] _, _ in
				OnMainThread {
					self?.setMultiSelecting(false)
				}
			}
			let button = UIButton(type: .system)
			button.setTitle(action.actionExtension.name, for: .normal)
			button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .footnote)
			button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
			let capturedAction = action
			button.addAction(UIAction { _ in
				capturedAction.run()
			}, for: .touchUpInside)
			multiSelectActionStack.addArrangedSubview(button)
		}
	}

	private func selectDeselectAll() {
		if selectedItemIDs.count == items.count {
			selectedItemIDs.removeAll()
			multiSelectionActionContext?.replace(items: [])
			collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false) }
		} else {
			selectedItemIDs = Set(items.map { itemIdentifier(for: $0) })
			multiSelectionActionContext?.replace(items: items)
			for index in items.indices {
				collectionView.selectItem(at: IndexPath(item: index, section: 0), animated: false, scrollPosition: [])
			}
		}
		refreshMultiselectActions()
		updateNavigationBarButtonItems()
		reconfigureVisibleCells()
	}

	// MARK: - Selection / open

	public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		true
	}

	public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard let itemID = dataSource.itemIdentifier(for: indexPath),
		      let item = itemsByID[itemID] else { return }

		if isMultiSelecting {
			selectedItemIDs.insert(itemID)
			multiSelectionActionContext?.add(item: item)
			refreshMultiselectActions()
			updateNavigationBarButtonItems()
			reconfigureVisibleCells()
			return
		}

		collectionView.deselectItem(at: indexPath, animated: true)
		_ = (item as DataItemSelectionInteraction).openItem?(from: self, with: clientContext, animated: true, pushViewController: true, completion: nil)
	}

	public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
		guard isMultiSelecting,
		      let itemID = dataSource.itemIdentifier(for: indexPath),
		      let item = itemsByID[itemID] else { return }
		selectedItemIDs.remove(itemID)
		multiSelectionActionContext?.remove(item: item)
		refreshMultiselectActions()
		updateNavigationBarButtonItems()
		reconfigureVisibleCells()
	}

	public func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
		guard !isMultiSelecting,
		      let itemID = dataSource.itemIdentifier(for: indexPath),
		      let item = itemsByID[itemID],
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
		guard !isMultiSelecting,
		      let itemID = dataSource.itemIdentifier(for: indexPath),
		      let item = itemsByID[itemID] as? DataItemSwipeInteraction else { return nil }
		return item.provideTrailingSwipeActions?(with: clientContext)
	}

	// MARK: - Drag & drop

	public func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		guard !isMultiSelecting,
		      let itemID = dataSource.itemIdentifier(for: indexPath),
		      let item = itemsByID[itemID] as? DataItemDragInteraction else { return [] }
		return item.provideDragItems(with: clientContext) ?? []
	}

	public func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
		canProvideDropTargets(for: session, target: collectionView)
	}

	public func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
		lastDropProposalDestinationIndexPath = destinationIndexPath
		updateDropTargets(for: session)

		if let destinationIndexPath,
		   let itemID = dataSource.itemIdentifier(for: destinationIndexPath),
		   let item = itemsByID[itemID] as? DataItemDropInteraction,
		   let proposal = item.allowDropOperation?(for: session, with: clientContext) {
			return proposal
		}

		if clientContext?.rootItem is DataItemDropInteraction {
			return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
		}

		return UICollectionViewDropProposal(operation: .cancel)
	}

	public func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
		let destinationIndexPath = coordinator.destinationIndexPath ?? lastDropProposalDestinationIndexPath
		var dropInteraction: DataItemDropInteraction?
		let dragItems = coordinator.items.map(\.dragItem)

		if let destinationIndexPath,
		   let itemID = dataSource.itemIdentifier(for: destinationIndexPath),
		   let item = itemsByID[itemID] as? DataItemDropInteraction {
			dropInteraction = item
		} else {
			dropInteraction = clientContext?.rootItem as? DataItemDropInteraction
		}

		dropInteraction?.performDropOperation(of: dragItems, with: clientContext) { _ in }
		cleanupDropTargets(for: coordinator.session, target: collectionView)
	}

	public func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
		cleanupDropTargets(for: session, target: collectionView)
	}

	public func canProvideDropTargets(for dropSession: UIDropSession, target: UIView) -> Bool {
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

	public func provideDropTargets(for dropSession: UIDropSession, target view: UIView) -> [OCDataItem & OCDataItemVersioning]? {
		let items = provideDropItems(from: dropSession)
		guard !items.isEmpty, let core = clientContext?.core else { return nil }
		dropTargetsActionContext = ActionContext(viewController: self, clientContext: clientContext, core: core, items: items, location: OCExtensionLocation(ofType: .action, identifier: .dropAction))
		guard let dropTargetsActionContext else { return nil }
		return Action.sortedApplicableActions(for: dropTargetsActionContext).map { $0.provideOCAction(singleVersion: true) }
	}

	public func cleanupDropTargets(for dropSession: UIDropSession, target view: UIView) {
		dropTargetsActionContext = nil
		if !isMultiSelecting {
			showMultiSelectActionBar(false)
			multiSelectActionStack.arrangedSubviews.forEach {
				multiSelectActionStack.removeArrangedSubview($0)
				$0.removeFromSuperview()
			}
		}
	}

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
		      let targets = provideDropTargets(for: session, target: collectionView),
		      !targets.isEmpty else { return }

		multiSelectActionStack.arrangedSubviews.forEach {
			multiSelectActionStack.removeArrangedSubview($0)
			$0.removeFromSuperview()
		}

		if let dropTargetsActionContext {
			let actions = Action.sortedApplicableActions(for: dropTargetsActionContext)
			for action in actions {
				let button = UIButton(type: .system)
				button.setTitle(action.actionExtension.name, for: .normal)
				button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .footnote)
				button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
				let capturedAction = action
				button.addAction(UIAction { _ in
					capturedAction.run()
				}, for: .touchUpInside)
				multiSelectActionStack.addArrangedSubview(button)
			}
		}

		showMultiSelectActionBar(true)
		_ = targets
	}

	// MARK: - Highlight

	private func highlightItemIfNeeded() {
		guard let highlightItemReference else { return }
		guard let match = items.first(where: { ($0.dataItemReference as NSObject).isEqual(highlightItemReference as NSObject) }) else { return }

		let id = itemIdentifier(for: match)
		guard let indexPath = dataSource.indexPath(for: id) else { return }

		collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
		collectionView.selectItem(at: indexPath, animated: true, scrollPosition: [])
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			self?.collectionView.deselectItem(at: indexPath, animated: true)
		}
		self.highlightItemReference = nil
	}
}

extension ClientItemViewController: FileBrowserContent {}
