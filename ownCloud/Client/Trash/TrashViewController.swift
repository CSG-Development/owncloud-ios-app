//
//  TrashViewController.swift
//  ownCloud
//
//  Copyright © 2025 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2025, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import ownCloudSDK
import ownCloudAppShared

private enum TrashSupplementaryKind {
	static let info = "trash-info-header"
	static let selectAll = "trash-select-all-header"
}

private final class TrashInfoHeaderView: UICollectionReusableView, Themeable {
	private let label = UILabel()
	private let bottomSeparator = UIView()
	private var themeRegistered = false

	override init(frame: CGRect) {
		super.init(frame: frame)
		label.translatesAutoresizingMaskIntoConstraints = false
		bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
		label.numberOfLines = 0
		label.textAlignment = .center
		label.font = UIFont.preferredFont(forTextStyle: .footnote)
		label.text = HCL10n.Trash.retentionNotice
		addSubview(label)
		addSubview(bottomSeparator)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
			label.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
			label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
			label.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor, constant: -12),

			bottomSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
			bottomSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
			bottomSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
			bottomSeparator.heightAnchor.constraint(equalToConstant: 1)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		label.textColor = HCColor.Content.textSecondary(collection.isDark)
		bottomSeparator.backgroundColor = HCColor.Content.border2(collection.isDark)
		backgroundColor = .clear
	}
}

private final class TrashSelectAllHeaderView: UICollectionReusableView, Themeable {
	var onToggle: (() -> Void)?

	private let titleLabel = UILabel()
	private let selectionButton = UIButton(type: .system)
	private var themeRegistered = false
	private var isDark = false
	private var allSelected = false

	override init(frame: CGRect) {
		super.init(frame: frame)

		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
		titleLabel.text = HCL10n.Trash.allItems

		selectionButton.translatesAutoresizingMaskIntoConstraints = false
		selectionButton.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
		selectionButton.accessibilityLabel = OCLocalizedString("Select All", nil)
		selectionButton.isPointerInteractionEnabled = true

		addSubview(selectionButton)
		addSubview(titleLabel)

		NSLayoutConstraint.activate([
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: selectionButton.leadingAnchor, constant: -12),

			selectionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			selectionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
			selectionButton.widthAnchor.constraint(equalToConstant: 24),
			selectionButton.heightAnchor.constraint(equalToConstant: 24),

			heightAnchor.constraint(equalToConstant: 42)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func setAllSelected(_ allSelected: Bool) {
		self.allSelected = allSelected
		updateSelectionIndicator()
	}

	private func updateSelectionIndicator() {
		selectionButton.setImage(TrashSelectionCheckbox.image(isSelected: allSelected, isDark: isDark), for: .normal)
	}

	@objc private func toggleTapped() {
		onToggle?()
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		isDark = collection.isDark
		titleLabel.textColor = HCColor.Content.textPrimary(collection.isDark)
		backgroundColor = .clear
		updateSelectionIndicator()
	}
}

final class TrashViewController: UIViewController, Themeable, UICollectionViewDelegate {

	private let clientContext: ClientContext
	private var items: [OCItem] = []
	private var folderStack: [OCItem] = []
	private var selectedItemIDs = Set<String>()
	private var isSelecting = false
	private var itemLayout: ItemLayout
	private var themeRegistered = false
	private var restoreSuccessToast: NetworkAvailabilityToastView?
	private var refreshControl: UIRefreshControl?
	private var foregroundObserver: NSObjectProtocol?
	private var connectionStatusObservation: NSKeyValueObservation?
	private var isShowingCachedContent = false
	/// Trash item IDs currently being permanently deleted; excluded from fetch results until the operation completes.
	private var pendingPermanentDeleteIDs = Set<String>()

	private lazy var navigationTitleLabel: ThemeCSSLabel = {
		let label = ThemeCSSLabel(withSelectors: [.title])
		label.font = UIFont.systemFont(ofSize: 20, weight: .regular)
		label.textAlignment = .left
		label.setContentHuggingPriority(.required, for: .horizontal)
		label.setContentCompressionResistancePriority(.required, for: .horizontal)
		return label
	}()

	private lazy var navigationTitleBarButtonItem: UIBarButtonItem = {
		UIBarButtonItem(customView: navigationTitleLabel)
	}()

	private lazy var collectionView: UICollectionView = {
		let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionViewLayout())
		collectionView.translatesAutoresizingMaskIntoConstraints = false
		collectionView.delegate = self
		collectionView.backgroundColor = .clear
		return collectionView
	}()

	private lazy var bottomActionBar: UIView = {
		let bar = UIView()
		bar.translatesAutoresizingMaskIntoConstraints = false
		bar.isHidden = true

		let stack = UIStackView(arrangedSubviews: [restoreButton, deleteButton])
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .horizontal
		stack.distribution = .fillEqually
		stack.spacing = 12
		bar.addSubview(stack)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: bar.layoutMarginsGuide.leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: bar.layoutMarginsGuide.trailingAnchor),
			stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 12),
			stack.bottomAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.bottomAnchor, constant: -12)
		])

		return bar
	}()

	private lazy var restoreButton: UIButton = {
		makeBottomActionButton(
			title: HCL10n.Trash.restore,
			style: .primary(configuration: .outlined),
			icon: HCIcon.restore
		) { [weak self] in
			self?.restoreSelectedItems()
		}
	}()

	private lazy var deleteButton: UIButton = {
		makeBottomActionButton(
			title: HCL10n.Trash.delete,
			style: .primary(configuration: .filled),
			icon: HCIcon.binx
		) { [weak self] in
			self?.confirmDeleteSelectedItems()
		}
	}()

	private lazy var layoutToggleButton: UIButton = {
		let button = UIButton(type: .system)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.addTarget(self, action: #selector(toggleItemLayout), for: .touchUpInside)
		button.accessibilityLabel = OCLocalizedString("Toggle layout", nil)
		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalToConstant: 28),
			button.heightAnchor.constraint(equalToConstant: 28)
		])
		return button
	}()

	private lazy var layoutBarButtonItem: UIBarButtonItem = {
		UIBarButtonItem(customView: layoutToggleButton)
	}()

	private lazy var selectBarButtonItem: UIBarButtonItem = {
		UIBarButtonItem(title: HCL10n.Trash.select, style: .plain, target: self, action: #selector(toggleSelectionMode))
	}()

	private lazy var dataSource: UICollectionViewDiffableDataSource<Int, String> = {
		let cellRegistration = UICollectionView.CellRegistration<TrashItemCell, String> { [weak self] cell, indexPath, itemID in
			guard let self, let item = self.item(for: itemID) else { return }

			cell.configure(
				item: item,
				core: self.clientContext.core,
				layout: self.itemLayout == .list ? .list : .grid,
				showsSelection: self.isSelecting,
				isSelected: self.selectedItemIDs.contains(itemID)
			)
		}

		let infoRegistration = UICollectionView.SupplementaryRegistration<TrashInfoHeaderView>(elementKind: TrashSupplementaryKind.info) { _, _, _ in }

		let selectAllRegistration = UICollectionView.SupplementaryRegistration<TrashSelectAllHeaderView>(elementKind: TrashSupplementaryKind.selectAll) { [weak self] supplementaryView, _, _ in
			guard let self else { return }
			supplementaryView.setAllSelected(self.allItemsSelected)
			supplementaryView.onToggle = { [weak self] in
				self?.toggleSelectAll()
			}
		}

		let dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { collectionView, indexPath, itemID in
			collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemID)
		}
		dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
			switch elementKind {
				case TrashSupplementaryKind.info:
					return collectionView.dequeueConfiguredReusableSupplementary(using: infoRegistration, for: indexPath)

				case TrashSupplementaryKind.selectAll:
					return collectionView.dequeueConfiguredReusableSupplementary(using: selectAllRegistration, for: indexPath)

				default:
					return nil
			}
		}
		return dataSource
	}()

	init(context: ClientContext) {
		self.clientContext = context
		self.itemLayout = ItemLayoutPreference.preferred
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		if themeRegistered {
			Theme.shared.unregister(client: self)
		}
	}

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()
		TrashDebugLogging.registerSDKLogObserverIfNeeded()

		view.addSubview(collectionView)
		view.addSubview(bottomActionBar)

		NSLayoutConstraint.activate([
			collectionView.topAnchor.constraint(equalTo: view.topAnchor),
			collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

			bottomActionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			bottomActionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bottomActionBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])

		navigationItem.rightBarButtonItems = [layoutBarButtonItem, selectBarButtonItem]
		updateLayoutBarButtonItem()
		updateNavigationTitle()
		updateNavigationBarButtonItems()
		applySnapshot(animated: false)

		let refresh = UIRefreshControl()
		refresh.addAction(UIAction { [weak self] _ in
			self?.performPullToRefresh()
		}, for: .valueChanged)
		refreshControl = refresh
		collectionView.refreshControl = refresh
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}

		syncItemLayoutWithPreference()
		updateNavigationTitle()
		updateNavigationBarButtonItems()
		browserNavigationViewController?.updateNavigation()
		fetchTrashedItems()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		installForegroundRefreshObserverIfNeeded()
		installConnectionStatusObserverIfNeeded()
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		removeForegroundRefreshObserver()
		connectionStatusObservation = nil
	}

	private func installForegroundRefreshObserverIfNeeded() {
		guard foregroundObserver == nil else { return }

		foregroundObserver = NotificationCenter.default.addObserver(
			forName: UIApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			guard let self, self.view.window != nil else { return }
			self.fetchTrashedItems(preserveSelection: self.isSelecting)
		}
	}

	private func installConnectionStatusObserverIfNeeded() {
		guard connectionStatusObservation == nil else { return }

		connectionStatusObservation = clientContext.core?.observe(\OCCore.connectionStatus, options: [.initial]) { [weak self] core, _ in
			guard let self else { return }

			OnMainThread {
				let wasCached = self.isShowingCachedContent
				self.isShowingCachedContent = core.connectionStatus != .online

				if wasCached && core.connectionStatus == .online {
					self.fetchTrashedItems(preserveSelection: self.isSelecting)
				}
			}
		}
	}

	private func removeForegroundRefreshObserver() {
		if let foregroundObserver {
			NotificationCenter.default.removeObserver(foregroundObserver)
			self.foregroundObserver = nil
		}
	}

	private func performPullToRefresh() {
		guard clientContext.core?.connectionStatus == .online else {
			refreshControl?.endRefreshing()
			return
		}

		fetchTrashedItems(preserveSelection: isSelecting)
	}

	private func syncItemLayoutWithPreference() {
		let preferred = ItemLayoutPreference.preferred
		let resolvedLayout = preferred == .list ? .list : preferred
		guard resolvedLayout != itemLayout else { return }

		itemLayout = resolvedLayout
		updateLayoutBarButtonItem()
		reloadLayout(animated: false)
		applySnapshot(animated: false, reconfigureAll: true)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		if isMovingFromParent || isBeingDismissed {
			if isSelecting {
				setSelecting(false)
			}

			if isMovingFromParent {
				folderStack.removeAll()
			}
		}
	}

	// MARK: - Themeable

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		let isDark = collection.isDark
		let appBackground = HCColor.Structure.appBackground(isDark)
		view.backgroundColor = appBackground
		collectionView.backgroundColor = collection.css.getColor(.fill, for: collectionView) ?? appBackground
		bottomActionBar.backgroundColor = appBackground
		layoutToggleButton.tintColor = HCColor.Content.textPrimary(isDark)
		navigationTitleLabel.textColor = HCColor.Content.textPrimary(isDark)
		updateBottomActionButtonStyles(isDark: isDark)
		if event != .initial {
			reloadLayout(animated: false)
		}
	}

	// MARK: - Data

	private var connection: OCConnection? {
		clientContext.core?.connection
	}

	private var allItemsSelected: Bool {
		!items.isEmpty && selectedItemIDs.count == items.count
	}

	private func itemIdentifier(for item: OCItem) -> String {
		item.path ?? item.fileID ?? item.eTag ?? UUID().uuidString
	}

	private func item(for identifier: String) -> OCItem? {
		items.first { itemIdentifier(for: $0) == identifier }
	}

	private func enrichTrashItems(_ items: [OCItem], core: OCCore?, connection: OCConnection?) -> [OCItem] {
		let driveID = core?.personalDrive?.identifier
			?? connection?.drives?.first(where: { $0.specialType == .personal })?.identifier
			?? connection?.drives?.first?.identifier

		guard let driveID else {
			TrashDebugLogging.log("TrashViewController.enrichTrashItems: no drive ID available")
			return items
		}

		for item in items where item.driveID == nil {
			item.driveID = driveID
		}

		for item in items {
			item.trashApplyPresentationMimeType()
		}

		return items
	}

	private func fetchTrashedItems(preserveSelection: Bool = false) {
		guard let core = clientContext.core else {
			refreshControl?.endRefreshing()
			return
		}

		let folder = TrashFeatures.folderNavigationEnabled ? folderStack.last : nil
		let previousSelection = preserveSelection ? selectedItemIDs : nil

		core.retrieveTrashedItems(inFolder: folder) { [weak self] error, fetchedItems, fromCache in
			OnMainThread {
				guard let self else { return }
				defer { self.refreshControl?.endRefreshing() }

				let resolvedItems = fetchedItems ?? []

				if fromCache {
					self.isShowingCachedContent = core.connectionStatus != .online
					self.applyFetchedTrashItems(resolvedItems, previousSelection: previousSelection)
					return
				}

				self.isShowingCachedContent = false

				if let error {
					if self.items.isEmpty {
						TrashDebugLogging.log("TrashViewController.fetchTrashedItems: error=\(error.localizedDescription)")
						self.showError(error, title: HCL10n.Trash.loadingError)
					}
					return
				}

				self.applyFetchedTrashItems(resolvedItems, previousSelection: previousSelection)
			}
		}
	}

	private func applyFetchedTrashItems(_ fetchedItems: [OCItem], previousSelection: Set<String>?) {
		var resolvedItems = fetchedItems
		if !pendingPermanentDeleteIDs.isEmpty {
			resolvedItems = resolvedItems.filter { !pendingPermanentDeleteIDs.contains(itemIdentifier(for: $0)) }
		}

		items = enrichTrashItems(resolvedItems, core: clientContext.core, connection: connection)
		TrashDebugLogging.log("TrashViewController.fetchTrashedItems: loaded \(items.count) item(s) cached=\(isShowingCachedContent)")
		for (index, item) in items.enumerated() {
			TrashDebugLogging.log(item: item, context: "TrashViewController.item[\(index)]")
		}

		if let previousSelection {
			let validIDs = Set(items.map { itemIdentifier(for: $0) })
			selectedItemIDs = previousSelection.intersection(validIDs)
		} else {
			selectedItemIDs.removeAll()
		}

		applySnapshot()
		updateNavigationTitle()
		updateNavigationBarButtonItems()
		updateActionButtonsEnabled()
	}

	private func applySnapshot(animated: Bool = true, reconfigureAll: Bool = false) {
		var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
		snapshot.appendSections([0])
		let itemIDs = items.map { itemIdentifier(for: $0) }
		snapshot.appendItems(itemIDs, toSection: 0)
		if reconfigureAll {
			snapshot.reconfigureItems(itemIDs)
		}
		dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
			self?.restoreCollectionViewSelection()
		}
	}

	private func makeCellConfiguration(for indexPath: IndexPath, itemID: String) {
		guard let cell = collectionView.cellForItem(at: indexPath) as? TrashItemCell,
		      let item = item(for: itemID) else { return }

		cell.configure(
			item: item,
			core: clientContext.core,
			layout: itemLayout == .list ? .list : .grid,
			showsSelection: isSelecting,
			isSelected: selectedItemIDs.contains(itemID)
		)
	}

	private func restoreCollectionViewSelection() {
		reconfigureVisibleCells()
	}

	private func reconfigureVisibleCells() {
		for indexPath in collectionView.indexPathsForVisibleItems {
			guard let itemID = dataSource.itemIdentifier(for: indexPath) else { continue }
			makeCellConfiguration(for: indexPath, itemID: itemID)
		}
	}

	// MARK: - Layout

	private func makeCollectionViewLayout() -> UICollectionViewLayout {
		UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
			guard let self else { return nil }

			let section: NSCollectionLayoutSection
			if self.itemLayout == .list {
				let itemSize = NSCollectionLayoutSize(
					widthDimension: .fractionalWidth(1.0),
					heightDimension: .absolute(TrashLayoutMetrics.listItemHeight)
				)
				let item = NSCollectionLayoutItem(layoutSize: itemSize)
				let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
				section = NSCollectionLayoutSection(group: group)
				section.interGroupSpacing = 0
			} else {
				section = TrashLayoutMetrics.makeGridSection(layoutEnvironment: layoutEnvironment)
			}

			let headerKind = self.isSelecting ? TrashSupplementaryKind.selectAll : TrashSupplementaryKind.info
			let headerHeightDimension: NSCollectionLayoutDimension = self.isSelecting
				? .absolute(42)
				: .estimated(60)
			let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: headerHeightDimension)
			let header = NSCollectionLayoutBoundarySupplementaryItem(
				layoutSize: headerSize,
				elementKind: headerKind,
				alignment: .top
			)
			section.boundarySupplementaryItems = [header]

			return section
		}
	}

	private func reloadLayout(animated: Bool) {
		collectionView.setCollectionViewLayout(makeCollectionViewLayout(), animated: animated)
		if !animated {
			collectionView.collectionViewLayout.invalidateLayout()
		}
	}

	@objc private func toggleItemLayout() {
		itemLayout = itemLayout == .list ? Self.preferredGridLayout : .list
		updateLayoutBarButtonItem()
		reloadLayout(animated: true)
		applySnapshot(animated: true, reconfigureAll: true)
	}

	private var layoutToggleTargetLayout: ItemLayout {
		itemLayout == .list ? Self.preferredGridLayout : .list
	}

	private func updateLayoutBarButtonItem() {
		let (label, icon) = layoutToggleTargetLayout.labelAndIcon()
		layoutToggleButton.setImage(icon?.withRenderingMode(.alwaysTemplate), for: .normal)
		layoutToggleButton.accessibilityLabel = label
	}

	private static var preferredGridLayout: ItemLayout {
		let preferred = ItemLayoutPreference.preferred
		return preferred == .list ? .grid : preferred
	}

	// MARK: - Selection mode

	private var hidesNavigationChromeDuringSelection: Bool {
		!UIDevice.current.isIpad
	}

	@objc private func toggleSelectionMode() {
		setSelecting(!isSelecting)
	}

	private func setSelecting(_ selecting: Bool) {
		guard isSelecting != selecting else { return }

		isSelecting = selecting
		collectionView.allowsMultipleSelection = selecting
		selectBarButtonItem.title = selecting ? HCL10n.Trash.cancel : HCL10n.Trash.select

		if !selecting {
			selectedItemIDs.removeAll()
		}

		bottomActionBar.isHidden = !selecting
		updateCollectionViewInsets()
		updateNavigationTitle()
		updateNavigationBarButtonItems()
		browserNavigationViewController?.updateNavigation()
		browserNavigationViewController?.setTabBarHidden(selecting && hidesNavigationChromeDuringSelection, animated: true)
		reloadLayout(animated: false)
		restoreCollectionViewSelection()
		updateActionButtonsEnabled()
	}

	private func updateCollectionViewInsets() {
		let bottomInset = isSelecting ? bottomActionBar.bounds.height : 0
		collectionView.contentInset.bottom = bottomInset
		collectionView.verticalScrollIndicatorInsets.bottom = bottomInset
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		updateCollectionViewInsets()
	}

	private func toggleSelectAll() {
		if allItemsSelected {
			selectedItemIDs.removeAll()
		} else {
			selectedItemIDs = Set(items.map { itemIdentifier(for: $0) })
		}
		updateActionButtonsEnabled()
		updateNavigationTitle()
		browserNavigationViewController?.updateNavigation()
		reloadSelectAllHeader()
		reconfigureVisibleCells()
	}

	private func reloadSelectAllHeader() {
		let indexPath = IndexPath(item: 0, section: 0)
		if let header = collectionView.supplementaryView(forElementKind: TrashSupplementaryKind.selectAll, at: indexPath) as? TrashSelectAllHeaderView {
			header.setAllSelected(allItemsSelected)
		}
	}

	private func updateActionButtonsEnabled() {
		let hasSelection = !selectedItemIDs.isEmpty
		restoreButton.isEnabled = hasSelection
		deleteButton.isEnabled = hasSelection
	}

	// MARK: - UICollectionViewDelegate

	func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
		if isSelecting { return true }
		return dataSource.itemIdentifier(for: indexPath) != nil
	}

	func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
		isSelecting
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		guard let itemID = dataSource.itemIdentifier(for: indexPath),
		      let item = item(for: itemID) else { return }

		if isSelecting {
			if selectedItemIDs.contains(itemID) {
				selectedItemIDs.remove(itemID)
			} else {
				selectedItemIDs.insert(itemID)
			}
			updateActionButtonsEnabled()
			updateNavigationTitle()
			browserNavigationViewController?.updateNavigation()
			reloadSelectAllHeader()
			makeCellConfiguration(for: indexPath, itemID: itemID)
			collectionView.deselectItem(at: indexPath, animated: false)
			return
		}

		collectionView.deselectItem(at: indexPath, animated: false)

		if item.type == .collection {
			guard TrashFeatures.folderNavigationEnabled else { return }
			openFolder(item)
			return
		}

		guard TrashFeatures.filePreviewEnabled else { return }
		openTrashItem(item)
	}

	func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
		// Selection state is managed explicitly in didSelectItemAt.
	}

	// MARK: - Actions

	private var selectedItems: [OCItem] {
		items.filter { selectedItemIDs.contains(itemIdentifier(for: $0)) }
	}

	private func restoreSelectedItems() {
		let itemsToRestore = selectedItems
		guard !itemsToRestore.isEmpty, let core = clientContext.core else { return }

		var pendingRestores = itemsToRestore.count
		var failedRestores = 0
		var firstError: Error?

		for item in itemsToRestore {
			restoreTrashItem(item, using: core) { [weak self] error in
				OnMainThread {
					guard let self else { return }

					if let error {
						failedRestores += 1
						if firstError == nil {
							firstError = error
						}
					}

					pendingRestores -= 1
					guard pendingRestores == 0 else { return }

					self.setSelecting(false)
					self.fetchTrashedItems()

					if failedRestores == 0 {
						self.showRestoreSuccessToast(restoredCount: itemsToRestore.count)
					} else if let firstError {
						self.showError(firstError, title: HCL10n.Trash.restoreError)
					}
				}
			}
		}
	}

	/// Restores a trashed item. Server-synced items use the connection API directly to avoid
	/// sync-engine progress wiring; pending-sync items still go through the sync engine to cancel the delete.
	private func restoreTrashItem(_ item: OCItem, using core: OCCore, completion: @escaping (Error?) -> Void) {
		if item.isPendingTrashItem {
			core.restoreTrashedItem(item) { error, _, _, _ in
				completion(error)
			}
			return
		}

		_ = core.connection.restoreTrashedItem(item) { error in
			completion(error)
		}
	}

	private func confirmDeleteSelectedItems() {
		let count = selectedItems.count
		guard count > 0 else { return }

		let alert = UIAlertController(
			title: HCL10n.Trash.Delete.title(count: count),
			message: nil,
			preferredStyle: .alert
		)
		alert.addAction(UIAlertAction(title: HCL10n.Trash.Delete.cancel, style: .cancel) { [weak self] _ in
			self?.syncSelectionChrome()
		})
		alert.addAction(UIAlertAction(title: HCL10n.Trash.Delete.confirm, style: .destructive) { [weak self] _ in
			self?.deleteSelectedItems()
		})
		present(alert, animated: true) { [weak self] in
			self?.syncSelectionChrome()
		}
	}

	private func deleteSelectedItems() {
		let itemsToDelete = selectedItems
		guard !itemsToDelete.isEmpty, let core = clientContext.core else { return }

		let deleteIDs = Set(itemsToDelete.map { itemIdentifier(for: $0) })
		pendingPermanentDeleteIDs.formUnion(deleteIDs)
		removeItemsFromDisplay(withIDs: deleteIDs)
		setSelecting(false)

		var pendingDeletes = itemsToDelete.count
		var failedDeletes = 0
		var firstError: Error?

		for item in itemsToDelete {
			core.permanentlyDeleteTrashedItem(item) { [weak self] error, _, _, _ in
				OnMainThread {
					guard let self else { return }

					if let error {
						failedDeletes += 1
						if firstError == nil {
							firstError = error
						}
					}

					pendingDeletes -= 1
					guard pendingDeletes == 0 else { return }

					self.pendingPermanentDeleteIDs.subtract(deleteIDs)
					self.fetchTrashedItems()

					if let firstError {
						self.showError(firstError, title: HCL10n.Trash.deleteError)
					}
				}
			}
		}
	}

	private func removeItemsFromDisplay(withIDs idsToRemove: Set<String>) {
		guard !idsToRemove.isEmpty else { return }

		items.removeAll { idsToRemove.contains(itemIdentifier(for: $0)) }
		selectedItemIDs.subtract(idsToRemove)
		applySnapshot()
		updateNavigationTitle()
		updateNavigationBarButtonItems()
		updateActionButtonsEnabled()
	}

	// MARK: - Errors

	private func showError(_ error: Error, title: String) {
		let alert = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: HCL10n.Trash.errorOk, style: .default) { [weak self] _ in
			self?.syncSelectionChrome()
		})
		present(alert, animated: true) { [weak self] in
			self?.syncSelectionChrome()
		}
	}

	private func syncSelectionChrome() {
		guard isSelecting else { return }
		if hidesNavigationChromeDuringSelection {
			browserNavigationViewController?.setTabBarHidden(true, animated: true)
		}
		updateNavigationTitle()
	}

	private func updateNavigationTitle() {
		let titleText: String
		if isSelecting {
			titleText = HCL10n.Trash.selectedTitle(selectedItemIDs.count)
		} else if TrashFeatures.folderNavigationEnabled, let currentFolder = folderStack.last {
			titleText = trashDisplayName(for: currentFolder)
		} else {
			titleText = HCL10n.Trash.titleWithCount(items.count)
		}

		navigationTitleLabel.text = titleText
		navigationTitleLabel.sizeToFit()

		title = nil
		navigationItem.title = nil
		navigationItem.titleView = nil
		navigationItem.navigationContent.remove(itemsWithIdentifier: "ios16-truncated-title-fix")
		navigationItem.navigationContent.remove(itemsWithIdentifier: "trash-title")

		let titleItem = NavigationContentItem(
			identifier: "trash-title",
			area: .left,
			priority: .highest,
			position: isSelecting ? .leading : .trailing,
			items: [navigationTitleBarButtonItem]
		)
		titleItem.visibleInPriorities = [.standard, .high, .highest]
		navigationItem.navigationContent.add(items: [titleItem])

		browserNavigationViewController?.updateNavigation()
		updateFolderBackNavigation()
	}

	private func trashDisplayName(for item: OCItem) -> String {
		if let trashName = item.value(forLocalAttribute: OCLocalAttribute.trashOriginalFilename) as? String, !trashName.isEmpty {
			return trashName
		}
		return item.name ?? ""
	}

	private func updateFolderBackNavigation() {
		navigationItem.navigationContent.remove(itemsWithIdentifier: "trash-folder-back")

		guard TrashFeatures.folderNavigationEnabled, !folderStack.isEmpty, !(isSelecting && hidesNavigationChromeDuringSelection) else { return }

		var configuration = UIButton.Configuration.plain()
		configuration.image = OCSymbol.icon(forSymbolName: "chevron.backward")
		configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8)

		let button = UIButton(
			configuration: configuration,
			primaryAction: UIAction { [weak self] _ in
				self?.navigateBackInTrash()
			}
		)
		button.contentHorizontalAlignment = .leading
		button.accessibilityLabel = OCLocalizedString("Back", nil)

		let backItem = NavigationContentItem(
			identifier: "trash-folder-back",
			area: .left,
			priority: .high,
			position: .leading,
			items: [UIBarButtonItem(customView: button)]
		)
		backItem.visibleInPriorities = [.standard, .high, .highest]
		navigationItem.navigationContent.add(items: [backItem])
	}

	private func openFolder(_ folder: OCItem) {
		guard TrashFeatures.folderNavigationEnabled, folder.type == .collection else { return }

		folderStack.append(folder)
		selectedItemIDs.removeAll()
		fetchTrashedItems()
	}

	private func openTrashItem(_ item: OCItem) {
		guard TrashFeatures.filePreviewEnabled else { return }
		TrashDebugLogging.log("[Preview] openTrashItem called: name=\(item.name ?? "nil") mimeType=\(item.mimeType ?? "nil") isTrash=\(item.isTrashItem) type=\(item.type.rawValue)")
		guard item.type == .file, !isSelecting, clientContext.core != nil else {
			TrashDebugLogging.log("[Preview] openTrashItem early-exit: type=\(item.type.rawValue) isSelecting=\(isSelecting) hasCore=\(clientContext.core != nil)")
			return
		}

		if let core = clientContext.core {
			let directOpenActionLocation = OCExtensionLocation(ofType: .action, identifier: .directOpen)
			let actionContext = ActionContext(
				viewController: self,
				clientContext: clientContext,
				core: core,
				items: [item],
				location: directOpenActionLocation,
				sender: nil
			)
			let directOpenActions = Action.sortedApplicableActions(for: actionContext)
			if let action = directOpenActions.first {
				TrashDebugLogging.log("[Preview] openTrashItem: using directOpen action \(type(of: action))")
				action.progressHandler = clientContext.actionProgressHandlerProvider?.makeActionProgressHandler()
				action.run()
				return
			}
		}

		let previewableItems = items.filter { $0.type == .file }.map { item in
			item.trashApplyPresentationMimeType()
			return item
		}
		let previewItem = item.trashApplyPresentationMimeType()
		TrashDebugLogging.log("[Preview] openTrashItem: pushing DisplayHostViewController previewItem.mimeType=\(previewItem.mimeType ?? "nil") previewItem.previewMIMEType=\(previewItem.previewMIMEType ?? "nil") previewableItems.count=\(previewableItems.count)")
		clientContext.pushViewControllerToNavigation(context: clientContext, provider: { context in
			let viewer = DisplayHostViewController(
				clientContext: context,
				selectedItem: previewItem,
				staticItems: previewableItems
			)
			viewer.hidesBottomBarWhenPushed = true
			viewer.progressSummarizer = context.progressSummarizer
			viewer.view.secureView(core: context.core)
			viewer.navigationBookmark = BrowserNavigationBookmark.from(dataItem: item, clientContext: context, restoreAction: .open)
			viewer.revoke(in: context, when: [.connectionClosed, .driveRemoved])
			return viewer
		}, push: true, animated: true)
	}

	private func navigateBackInTrash() {
		guard TrashFeatures.folderNavigationEnabled, !folderStack.isEmpty else { return }

		folderStack.removeLast()
		selectedItemIDs.removeAll()
		if isSelecting {
			setSelecting(false)
		}
		fetchTrashedItems()
	}

	private func updateNavigationBarButtonItems() {
		if isSelecting {
			navigationItem.rightBarButtonItems = [selectBarButtonItem]
			selectBarButtonItem.isEnabled = true
		} else {
			navigationItem.rightBarButtonItems = [layoutBarButtonItem, selectBarButtonItem]
			selectBarButtonItem.isEnabled = !items.isEmpty
		}
	}

	private func makeBottomActionButton(
		title: String,
		style: HCButtonStyle,
		icon: UIImage?,
		action: @escaping () -> Void
	) -> UIButton {
		let button = UIButton()
		button.translatesAutoresizingMaskIntoConstraints = false
		button.contentHorizontalAlignment = .center
		button.heightAnchor.constraint(equalToConstant: 40).isActive = true
		applyBottomActionButtonStyle(button, title: title, style: style, icon: icon)
		button.addAction(UIAction { _ in action() }, for: .touchUpInside)
		return button
	}

	private func applyBottomActionButtonStyle(_ button: UIButton, title: String, style: HCButtonStyle, icon: UIImage?) {
		button.applyTrashBottomBarStyle(title: title, style: style, icon: icon)
	}

	private func updateBottomActionButtonStyles(isDark: Bool) {
		applyBottomActionButtonStyle(restoreButton, title: HCL10n.Trash.restore, style: .primary(configuration: .outlined), icon: HCIcon.restore)
		applyBottomActionButtonStyle(deleteButton, title: HCL10n.Trash.delete, style: .primary(configuration: .filled), icon: HCIcon.binx)
	}

	private func showRestoreSuccessToast(restoredCount: Int) {
		restoreSuccessToast?.removeFromSuperview()

		let toast = NetworkAvailabilityToastView(message: HCL10n.Trash.restoreSuccess(restoredCount), style: .snackbar)
		toast.configure(for: nil)
		toast.alpha = 0
		toast.onDismiss = { [weak self] in
			UIView.animate(withDuration: 0.2) {
				toast.alpha = 0
			} completion: { _ in
				toast.removeFromSuperview()
				if self?.restoreSuccessToast === toast {
					self?.restoreSuccessToast = nil
				}
			}
		}
		restoreSuccessToast = toast
		view.addSubview(toast)
		toast.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			toast.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
			toast.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
			toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
		])

		UIView.animate(withDuration: 0.25) {
			toast.alpha = 1
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak toast] in
			guard let toast, toast.superview != nil else { return }
			toast.onDismiss?()
		}
	}
}

extension TrashViewController: BrowserNavigationSidebarToggleControlling {
	var suppressesBrowserSidebarToggle: Bool {
		isSelecting && hidesNavigationChromeDuringSelection
	}
}

extension TrashViewController: BrowserNavigationTabBarVisibilityControlling {
	var prefersTabBarHidden: Bool {
		isSelecting && hidesNavigationChromeDuringSelection
	}
}

private extension UIButton {
	func applyTrashBottomBarStyle(title: String, style: HCButtonStyle, icon: UIImage?) {
		contentHorizontalAlignment = .center

		let updateConfiguration: (UIControl.State, inout UIButton.Configuration?) -> Void = { state, configuration in
			let isDark = Theme.shared.activeCollection.isDark
			let isDisabled = state.contains(.disabled)

			var config = UIButton.Configuration.filled()
			config.cornerStyle = .capsule
			config.titleAlignment = .center
			config.imagePadding = 8
			config.imagePlacement = .leading
			config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)

			let backgroundColor: UIColor?
			let foregroundColor: UIColor
			if isDisabled {
				foregroundColor = HCColor.Content.gray2(isDark)
				switch style {
					case .primary(configuration: .filled):
						backgroundColor = HCColor.Content.disabledBackground(isDark)
					default:
						backgroundColor = .clear
				}
			} else {
				backgroundColor = self.trashActionBackgroundColor(style: style, isDark: isDark)
				foregroundColor = self.trashActionForegroundColor(style: style, isDark: isDark)
			}

			config.image = icon?.withTintColor(foregroundColor, renderingMode: .alwaysOriginal)

			if style.isOutlined {
				config.background.strokeWidth = 1.0
				config.background.strokeOutset = 0.5
				config.background.strokeColor = foregroundColor
			}
			config.background.backgroundColor = backgroundColor ?? .clear
			var attributedTitle = AttributedString(title)
			attributedTitle.foregroundColor = foregroundColor
			attributedTitle.font = UIFont.systemFont(ofSize: 14, weight: .medium)
			config.attributedTitle = attributedTitle
			config.baseForegroundColor = foregroundColor

			configuration = config
		}

		updateConfiguration(.normal, &configuration)
		configurationUpdateHandler = { button in
			updateConfiguration(button.state, &button.configuration)
		}
	}

	private func trashActionBackgroundColor(style: HCButtonStyle, isDark: Bool) -> UIColor? {
		switch style {
			case .primary(configuration: .filled):
				return isDark ? HCColor.Blue.lighten2 : HCColor.Blue.darken2
			case .primary(configuration: .outlined):
				return .clear
			case .secondary(configuration: .filled):
				return isDark ? HCColor.white : HCColor.Grey.darken4
			default:
				return .clear
		}
	}

	private func trashActionForegroundColor(style: HCButtonStyle, isDark: Bool) -> UIColor {
		switch style {
			case .primary(configuration: .filled), .secondary(configuration: .filled):
				return isDark ? HCColor.Text.lightModePrimary : HCColor.Text.darkModePrimary
			case .primary(configuration: .outlined):
				return isDark ? HCColor.Blue.lighten2 : HCColor.Blue.darken2
			default:
				return HCColor.Content.textPrimary(isDark)
		}
	}
}
