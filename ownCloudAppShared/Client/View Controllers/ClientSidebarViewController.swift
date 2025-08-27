//
//  ClientSidebarViewController.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 21.11.22.
//  Copyright © 2022 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2018, ownCloud GmbH.
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

extension ThemeCSSSelector {
	static let logo = ThemeCSSSelector(rawValue: "logo")
}

public class ClientSidebarViewController: CollectionSidebarViewController, NavigationRevocationHandler {
	public var accountsSectionSubscription: OCDataSourceSubscription?
	public var accountsControllerSectionSource: OCDataSourceMapped?
	public var controllerConfiguration: AccountController.Configuration
	private var query: OCQuery?

	private var footerView = HCSidebarFooterView(frame: .zero)
	private var footerViewDouble = HCSidebarFooterView(frame: .zero)
	private var contentSizeObservation: NSKeyValueObservation?

	private let updateAvailableSpaceGate = RunGate()

	private var bookmarksSubscription: OCDataSourceSubscription?
	private var statusNotificationObserver: NSObjectProtocol?
	private var connectionClosedGateResetAction: NavigationRevocationAction?

	private func installConnectionClosedGateResetAction() {
		// Unregister any previous action
		connectionClosedGateResetAction?.unregister(for: self, globally: true)

		// Create a fresh action that will re-install itself after firing
		let action = NavigationRevocationAction(eventMatcher: { event in
			if case .connectionClosed(_) = event { return true }
			return false
		}, action: { [weak self] _, _ in
			guard let self else { return }
			self.updateAvailableSpaceGate.reset()
			DispatchQueue.main.async {
				self.footerView.bytesUsed = nil
				self.footerView.bytesRemaining = nil
				self.footerViewDouble.bytesUsed = nil
				self.footerViewDouble.bytesRemaining = nil
			}
			// Install again for subsequent events
			self.installConnectionClosedGateResetAction()
		})

		connectionClosedGateResetAction = action
		action.register(for: self, globally: true)
	}

	public init(context inContext: ClientContext, controllerConfiguration: AccountController.Configuration) {
		self.controllerConfiguration = controllerConfiguration

		super.init(context: inContext, sections: nil, navigationPusher: { sideBarViewController, viewController, animated in
			// Push new view controller to detail view controller
			if let contentNavigationController = inContext.navigationController {
				contentNavigationController.setViewControllers([viewController], animated: false)
				sideBarViewController.splitViewController?.showDetailViewController(contentNavigationController, sender: sideBarViewController)
			}
		})
	}

	required public init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	var selectionChangeObservation: NSKeyValueObservation?
	var combinedSectionsDatasource: OCDataSourceComposition?

	var shouldShowDouble: Bool = false {
		didSet {
			guard oldValue != shouldShowDouble else { return }
			updateFooter()
		}
	}

	public var onSettingsTap: (() -> Void)?
	public var onSignoutTap: (() -> Void)?
	public var onEditTap: (() -> Void)?

	public override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		updateShouldShowDouble()
		updateAvailableSpace()
	}

	override public func viewDidLoad() {
		super.viewDidLoad()

		collectionView.delegate = self

		// Disable dragging of items, so keyboard control does
		// not include "Drag Item" in the accessibility actions
		// invoked with Tab + Z
		dragInteractionEnabled = false

		// Set up AccountsControllerSource
		accountsControllerSectionSource = OCDataSourceMapped(source: nil, creator: { [weak self] (_, bookmarkDataItem) in
			if let bookmark = bookmarkDataItem as? OCBookmark, let self = self, let clientContext = self.clientContext {
				let controller = AccountController(bookmark: bookmark, context: clientContext, configuration: self.controllerConfiguration)
				self.headerView.bookmark = bookmark
				self.headerView.onEditTap = self.onEditTap
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
					self.updateAvailableSpace()
				}
				return AccountControllerSection(with: controller)
			}

			return nil
		}, updater: nil, destroyer: { _, bookmarkItemRef, accountController in
			// Safely disconnect account controller if currently connected
			if let accountController = accountController as? AccountController {
				accountController.destroy() // needs to be called since AccountController keeps a reference to itself otherwise
			}
		}, queue: .main)

		accountsControllerSectionSource?.trackItemVersions = true
		accountsControllerSectionSource?.source = OCBookmarkManager.shared.bookmarksDatasource

		// Combined data source
		if let accountsControllerSectionSource {
			var sources: [OCDataSource] = [ accountsControllerSectionSource ]

			if let brandingElementDataSource {
				sources.insert(brandingElementDataSource, at: 0)
			}

			if let sidebarLinksDataSource {
				sources.append(sidebarLinksDataSource)
			}

			if let customActionsDataSource {
				sources.append(customActionsDataSource)
			}

			if let footerDataSource {
				sources.append(footerDataSource)
			}

			if sources.count > 1 {
				combinedSectionsDatasource = OCDataSourceComposition(sources: sources)
			}
		}

		// Set up Collection View
		sectionsDataSource = combinedSectionsDatasource ?? accountsControllerSectionSource
		navigationItem.largeTitleDisplayMode = .never
		navigationItem.titleView = ClientSidebarViewController.buildNavigationLogoView()

		// Add 10pt space at the top so that the first section's account doesn't "stick" to the top
		collectionView.contentInset.top += 10

		view.addSubview(footerView)
		footerView.snp.makeConstraints {
			$0.leading.equalToSuperview().offset(16)
			$0.trailing.equalToSuperview().offset(-16)
			$0.bottom.equalToSuperview().offset(-12)
		}

		// Temporary, ugly fix for "empty bookmarks list in sidebar"
		// Actual issue, as far as understood, is that if that error occurs, the created AccountControllerSections
		// have no items in them - despite the underlying data sources having them. Until that mystery isn't fully solved
		// a force-refresh of the underlying (root) datasource is a way to mitigate the issue's negative outcome (no accounts in list)
		OnMainThread { // Wait for first, regular main thread iteraton
			OnMainThread(after: 1) { // wait one more second
				// Force refresh the bookmarks data source
				if self.collectionView.numberOfSections < OCBookmarkManager.shared.bookmarks.count ||
				   ((self.collectionView.numberOfSections > 0) && (self.collectionView.numberOfItems(inSection: 0) == 0)) {
					self.forceReloadBookmarks()
				}
			}
		}

		contentSizeObservation = collectionView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
			self?.updateShouldShowDouble()
		}
		updateFooter()

		bookmarksSubscription = OCBookmarkManager.shared.bookmarksDatasource.subscribe(updateHandler: { _ in
			DispatchQueue.main.async {
				self.headerView.bookmark = OCBookmarkManager.shared.bookmarks.first
				self.updateAvailableSpace()
			}
		}, on: nil, trackDifferences: false, performInitialUpdate: true)

		// Observe connection status changes (e.g., after login) to refresh quota
		statusNotificationObserver = NotificationCenter.default.addObserver(forName: AccountConnection.StatusChangedNotification, object: nil, queue: .main, using: { [weak self] _ in
			self?.updateAvailableSpace()
			self?.forceReloadBookmarks()
		})

		// Reset the gate and clear footer when a connection is closed (e.g., during logout)
		installConnectionClosedGateResetAction()
	}

	deinit {
		accountsControllerSectionSource?.source = nil // Clear all AccountController instances from the controller and make OCDataSourceMapped call the destroyer
		connectionClosedGateResetAction?.unregister(for: self, globally: true)
		connectionClosedGateResetAction = nil
	}

	public func forceReloadBookmarks() {
		guard let bookmarks = OCBookmarkManager.shared.bookmarks as? [OCDataItem & OCDataItemVersioning] else { return }
		(OCBookmarkManager.shared.bookmarksDatasource as? OCDataSourceArray)?.setVersionedItems(bookmarks)
	}

	public func updateAvailableSpace() {
		updateAvailableSpaceGate.runIfIdle { [weak self] done in
			let bookmark = self?.focusedBookmark ?? OCBookmarkManager.shared.bookmarks.first
			guard
				let bookmark,
				let connection = AccountConnectionPool.shared.connection(for: bookmark),
				let ocConnection = connection.core?.connection
			else {
				DispatchQueue.main.async {
					self?.footerView.bytesUsed = nil
					self?.footerView.bytesRemaining = nil
					self?.footerViewDouble.bytesUsed = nil
					self?.footerViewDouble.bytesRemaining = nil
				}
				done()
				return
			}

			let rootLocation = OCLocation.legacyRoot
			ocConnection.retrieveItemList(at: rootLocation, depth: 0, options: [:]) { [weak self] error, items in
				guard let self = self else {
					done()
					return
				}

				if let item = items?.first {
					DispatchQueue.main.async {
						self.footerView.bytesUsed = item.quotaBytesUsed?.int64Value
						self.footerViewDouble.bytesUsed = item.quotaBytesUsed?.int64Value
						self.footerView.bytesRemaining = item.quotaBytesRemaining?.int64Value
						self.footerViewDouble.bytesRemaining = item.quotaBytesRemaining?.int64Value
					}
				} else {
					DispatchQueue.main.async {
						self.footerView.bytesUsed = nil
						self.footerView.bytesRemaining = nil
						self.footerViewDouble.bytesUsed = nil
						self.footerViewDouble.bytesRemaining = nil
					}
				}
				done()
			}
		}
	}

	// MARK: - NavigationRevocationHandler
	public func handleRevocation(event: NavigationRevocationEvent, context: ClientContext?, for viewController: UIViewController) {
		if let history = sidebarContext.browserController?.history {
			// Log.debug("Revoke view controller: \(viewController) \(viewController.navigationItem.titleLabelText)")
			var hasHistoryItem = false

			// A view controller may appear more than once in history, so if a view controller is to be removed,
			// make sure that all history items for it are removed
			while let historyItem = history.item(for: viewController) {
				history.remove(item: historyItem, completion: nil)
				hasHistoryItem = true
			}

			// Dismiss view controllers that are being presented but are not part of the sidebar browser controller's history
			if !hasHistoryItem {
				if viewController.presentingViewController != nil {
					dismissDeep(viewController: viewController)
				}
			}
		}
	}

	func dismissDeep(viewController: UIViewController) {
		if viewController.presentingViewController != nil {
			var dismissStartViewController: UIViewController? = viewController

			while let deeperViewController = dismissStartViewController?.presentedViewController {
				dismissStartViewController = deeperViewController
			}

			dismissStartViewController?.dismiss(animated: true, completion: { [weak self] in
				self?.dismissDeep(viewController: viewController)
			})
		}
	}

	// MARK: - Selected Bookmark
	private var focusedBookmarkNavigationRevocationAction: NavigationRevocationAction?

	@objc public dynamic var focusedBookmark: OCBookmark? {
		didSet {
			Log.debug("New focusedBookmark:: \(focusedBookmark?.displayName ?? "-")")
			updateAvailableSpace()
		}
	}

	public override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		super.collectionView(collectionView, didSelectItemAt: indexPath)

		var newFocusedBookmark: OCBookmark?

		if let accountControllerSection = self.sectionOfCurrentSelection as? AccountControllerSection {
			newFocusedBookmark = accountControllerSection.accountController.connection?.bookmark

			if let newFocusedBookmarkUUID = newFocusedBookmark?.uuid {
				focusedBookmarkNavigationRevocationAction = NavigationRevocationAction(triggeredBy: [.connectionClosed(bookmarkUUID: newFocusedBookmarkUUID)], action: { [weak self] event, action in
					if self?.focusedBookmark?.uuid == newFocusedBookmarkUUID {
						self?.focusedBookmark = nil
					}
				})
				focusedBookmarkNavigationRevocationAction?.register(globally: true)
			}
		}

		focusedBookmark = newFocusedBookmark
	}

	public var brandingElementDataSource: OCDataSourceArray? {
		nil
	}

	public var customActionsDataSource: OCDataSourceArray? {
		// Create custom actions
		let settingsAction = OCAction(
			title: OCLocalizedString("Settings", nil),
			icon: UIImage(named: "settings_thin", in: Bundle.sharedAppBundle, with: nil),
			action: { [weak self] _, _, completion in
			self?.onSettingsTap?()
			completion(nil)
		})
		settingsAction.automaticDeselection = true

		let signOutAction = OCAction(title: HCL10n.Sidebar.signOut, icon: UIImage(named: "sign_out", in: Bundle.sharedAppBundle, with: nil), action: { [weak self] _, _, completion in
			self?.onSignoutTap?()
			completion(nil)
		})
		signOutAction.automaticDeselection = true

		// Create section with actions
		let actionsDataSource = OCDataSourceArray(items: [settingsAction, signOutAction])
		let actionsSection = CollectionViewSection(identifier: "custom-actions-section",
												 dataSource: actionsDataSource,
												 cellStyle: CollectionViewCellStyle(with: .sideBar),
												 cellLayout: .list(appearance: .sidebar),
												 clientContext: clientContext)

		let separatorView = HCSeparatorView(frame: .zero)
		let separatorContainerView = UIView()
		separatorContainerView.backgroundColor = .clear
		separatorContainerView.addSubview(separatorView)
		separatorContainerView.snp.makeConstraints {
			$0.height.equalTo(25)
		}
		separatorView.snp.makeConstraints {
			$0.height.equalTo(1)
			$0.center.leading.equalToSuperview()
		}

		let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(1))
		let supplementaryItem = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: CollectionViewSupplementaryItem.ElementKind.view, alignment: .top)
		supplementaryItem.pinToVisibleBounds = false
		supplementaryItem.zIndex = 200
		actionsSection.boundarySupplementaryItems = [
			CollectionViewSupplementaryItem(supplementaryItem: supplementaryItem, content: separatorContainerView)
		]
		return OCDataSourceArray(items: [actionsSection])
	}

	public var footerDataSource: OCDataSourceArray? {
		let supplementaryFooterItem = NSCollectionLayoutBoundarySupplementaryItem(
			layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(1)),
			elementKind: CollectionViewSupplementaryItem.ElementKind.view,
			alignment: .bottom
		)
		supplementaryFooterItem.pinToVisibleBounds = false
		let footerSection = CollectionViewSection(
			identifier: "footer-section",
			dataSource: nil,
			cellStyle: CollectionViewCellStyle(with: .footer),
			cellLayout: .list(appearance: .sidebar),
			clientContext: clientContext
		)

		footerSection.boundarySupplementaryItems = [
			CollectionViewSupplementaryItem(supplementaryItem: supplementaryFooterItem, content: footerViewDouble)
		]
		return OCDataSourceArray(items: [footerSection])
	}

	public var sidebarLinksDataSource: OCDataSourceArray? {
		if let sidebarLinks = Branding.shared.sidebarLinks {
			let actions = sidebarLinks.compactMap { link in

				var image: UIImage?
				if let symbol = link.symbol, let anImage = OCSymbol.icon(forSymbolName: symbol) {
					image = anImage
				} else if let imageName = link.image, let anImage = UIImage(named: imageName) {
					image = anImage.scaledImageFitting(in: CGSize(width: 30, height: 30))
				}

				let action = OCAction(title: link.title, icon: image, action: { [weak self] _, _, completion in
					if let self = self {
						self.openURL(link.url)
					}
					completion(nil)
				})
				action.automaticDeselection = true

				return action
			}

			let linksDataSource = OCDataSourceArray(items: actions)

			let linksSection = CollectionViewSection(identifier: "links-section", dataSource: linksDataSource, cellStyle: CollectionViewCellStyle(with: .sideBar), cellLayout: .list(appearance: .sidebar), clientContext: clientContext)

			if let title = Branding.shared.sidebarLinksTitle {
				linksSection.boundarySupplementaryItems = [
					.mediumTitle(title, pinned: true)
				]
			}
			return OCDataSourceArray(items: [ linksSection ])
		}

		return nil
	}

	// MARK: - Reordering bookmarks
	func dataItem(for itemRef: CollectionViewController.ItemRef) -> OCDataItem? {
		let (dataItemRef, sectionID) = unwrap(itemRef)

		if let sectionID, let section = sectionsByID[sectionID] {
			if let record = try? section.dataSource?.record(forItemRef: dataItemRef) {
				return record.item
			}
		}

		return nil
	}

	public override func configureDataSource() {
		super.configureDataSource()

		collectionViewDataSource.reorderingHandlers.canReorderItem = { (itemRef) in
			// Log.debug("Can reorder \(itemRef)")
			return true
		}

		collectionViewDataSource.reorderingHandlers.didReorder = { [weak self] transaction in
			Log.debug("Did reorder \(transaction)")

			guard let self else { return }

			var reorderedBookmarks: [OCBookmark] = []

			for collectionItemRef in transaction.finalSnapshot.itemIdentifiers {
				if let accountController = self.dataItem(for: collectionItemRef) as? AccountController,
				   let bookmark = accountController.bookmark,
				   let managedBookmark = OCBookmarkManager.shared.bookmark(for: bookmark.uuid) {
					reorderedBookmarks.append(managedBookmark)
					Log.debug("Bookmark: \(bookmark.shortName)")
				}
			}

			if OCBookmarkManager.shared.bookmarks.count == reorderedBookmarks.count {
				OCBookmarkManager.shared.replaceBookmarks(reorderedBookmarks)
			}
		}
	}

	public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
		super.scrollViewDidScroll(scrollView)

		updateShouldShowDouble()
	}

	private func updateShouldShowDouble() {
		let viewportHeight = collectionView.bounds.size.height
		let contentHeight = collectionView.contentSize.height
		shouldShowDouble = viewportHeight < contentHeight
	}

	private func updateFooter() {
		UIView.animate(withDuration: 0.3) {
			self.footerView.alpha = self.shouldShowDouble ? 0 : 1
			self.footerViewDouble.alpha = 1 - self.footerView.alpha
			var insets = self.collectionView.contentInset
			insets.bottom = self.shouldShowDouble ? 12 : 0
			self.collectionView.contentInset = insets
		}
	}
}

// MARK: - Branding
extension ClientSidebarViewController {
	static public func buildNavigationLogoView() -> ThemeCSSView {
		HCNavigationLogoView(frame: .zero)
	}
}
