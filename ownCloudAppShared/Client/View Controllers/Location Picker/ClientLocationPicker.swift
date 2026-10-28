//
//  ClientLocationPicker.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 29.11.22.
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

// MARK: - OCLocation additions
extension OCLocation {
	// LocationLevel property
	public var clientLocationLevel: ClientLocationPicker.LocationLevel {
		if path != nil, !isRoot {
			return .folder
		} else if driveID != nil {
			return .drive
		} else if bookmarkUUID != nil {
			return .account
		}

		return .accounts
	}

	// OCLocation creation with app terminology
	public static var accounts: OCLocation {
		return OCLocation()
	}

	public static func account(_ bookmark: OCBookmark) -> OCLocation {
		return OCLocation(bookmarkUUID: bookmark.uuid, driveID: nil, path: nil)
	}

	public static func drive(_ driveID: String, bookmark: OCBookmark) -> OCLocation {
		return OCLocation(bookmarkUUID: bookmark.uuid, driveID: driveID, path: "/")
	}

	public static func folder(_ item: OCItem, bookmark: OCBookmark) -> OCLocation {
		let folderLocation = item.location!

		if folderLocation.bookmarkUUID == nil {
			folderLocation.bookmarkUUID = bookmark.uuid
		}

		return folderLocation
	}
}

// MARK: - Location Picker
public class ClientLocationPicker : NSObject {
	// MARK: - Types
	public enum LocationLevel: CaseIterable {
		case accounts	// Choice between accounts is possible
		case account	// Choice within a single account is possible
		case drive	// Choice within a single drive is possible
		case folder	// Choice within a folder (+ subfolders) is possible
	}

	public typealias LocationFilter = (_ location: OCLocation, _ context: ClientContext?) -> Bool
	public typealias ChoiceHandler = (_ chosenItem: OCItem?, _ location: OCLocation?, _ context: ClientContext?, _ cancelled: Bool) -> Void

	// MARK: - Options
	public var showFavorites: Bool
	public var recentLocations: [OCLocation]?

	public var startLocation: OCLocation
	public var maximumLevel: LocationLevel

	public var conflictItems: [OCItem]?
	public var choiceHandler: ChoiceHandler?

	public var allowedLocationFilter: LocationFilter? // Determines which locations can be picked by the user
	public var navigationLocationFilter: LocationFilter? // Determines which locations can be selected by the user during navigation

	public var allowFileSelection: Bool = false

	public var headerView: UIView?
	var headerViewTitleElement: ComposedMessageElement?
	var headerViewSubtitleElement: ComposedMessageElement?

	public var headerTitle: String? {
		didSet {
			headerViewTitleElement?.text = headerTitle
		}
	}
	public var headerSubTitle: String? {
		didSet {
			headerViewSubtitleElement?.text = headerSubTitle
		}
	}

	public var selectButtonTitle: String
	public var selectPrompt: String?
	public var accountControllerConfiguration: AccountController.Configuration?

	/// Becomes true once the root of the picker is a folder listing, so a later
	/// drive/core update does not replace a list the user is already browsing.
	private var didPresentFolderList = false
	private var didRequestConnection = false
	private var resolvedPersonalDriveID: String?
	private var personalDriveSubscription: OCDataSourceSubscription?

	// MARK: - Init
	public init(location: OCLocation, maximumLevel: LocationLevel = .folder, showFavorites: Bool = true, showRecents: Bool = true, selectButtonTitle: String?, selectPrompt: String? = nil, headerTitle: String? = nil, headerSubTitle: String? = nil, headerView: UIView? = nil, requiredPermissions: OCItemPermissions? = [.createFile], avoidConflictsWith conflictItems: [OCItem]?, choiceHandler: @escaping ChoiceHandler) {
		self.startLocation = location
		self.showFavorites = showFavorites
		self.selectButtonTitle = selectButtonTitle ?? OCLocalizedString("Select folder", nil)
		self.selectPrompt = selectPrompt
		self.headerTitle = headerTitle
		self.headerSubTitle = headerSubTitle
		self.conflictItems = conflictItems
		self.maximumLevel = maximumLevel
		self.headerView = headerView

		self.accountControllerConfiguration = .pickerConfiguration

		super.init()

		if location.clientLocationLevel == .account {
			// No point showing the account pill if its the only account being shown
			// self.accountControllerConfiguration?.showAccountPill = false
		}

		self.choiceHandler = choiceHandler

		// Create header view if title is specified, but headerView isn't
		if let headerTitle, headerView == nil {
			headerViewTitleElement = .text(headerTitle, style: .system(textStyle: .title2, weight: .bold), alignment: .leading, cssSelectors: [.title])

			var elements: [ComposedMessageElement] = [ headerViewTitleElement! ]

			if let headerSubTitle {
				headerViewSubtitleElement = .text(headerSubTitle, style: .systemSecondary(textStyle: .body), alignment: .leading, cssSelectors: [.subtitle])
				elements.append(headerViewSubtitleElement!)
			}

			let composedHeaderView = ComposedMessageView(elements: elements)
			composedHeaderView.cssSelectors = [.header]
			self.headerView = composedHeaderView
		}

		// Create allowedLocationFilter and navigationLocationFilter from conflictItems
		var effectiveConflictItems = conflictItems

		if conflictItems == nil, requiredPermissions != nil {
			// Ensure .allowedLocationFilter is also created with empty conflictItems -
			// if there are permission requirements to check for
			effectiveConflictItems = []
		}

		if let effectiveConflictItems {
			var navigationPathFilter : LocationFilter?

			let folderItemLocations = effectiveConflictItems.filter({ (item) -> Bool in
				return item.type == .collection && item.path != nil && !item.isRoot
			}).map { (item) -> OCLocation in
				return item.location!
			}
			let itemParentLocations = effectiveConflictItems.filter({ (item) -> Bool in
				return item.location?.parent != nil
			}).map { (item) -> OCLocation in
				return item.location!.parent!
			}

			if folderItemLocations.count > 0 {
				navigationPathFilter = { (targetLocation, _) in
					return !folderItemLocations.contains(targetLocation)
				}
			}

			allowedLocationFilter = { (targetLocation, context) in
				// Disallow all paths as target that are parent of any of the items
				if itemParentLocations.contains(targetLocation) {
					return false
				}

				// Check that destination meets permission requirements
				if let requiredPermissions {
					if let item = try? context?.core?.cachedItem(at: targetLocation) {
						return item.permissions.contains(requiredPermissions)
					}
				}

				return true
			}

			navigationLocationFilter = navigationPathFilter
		}
	}

	// MARK: - Permission checks
	func checkPermission(context: ClientContext?, dataItemRecord: OCDataItemRecord?, interaction: ClientItemInteraction, viewController: UIViewController?) -> Bool {
		switch interaction {
			case .selection:
				if let item = dataItemRecord?.item as? OCItem {
					if item.type == .file {
						if allowFileSelection,
						   let locationPickerViewController = viewController?.parent?.parent as? ClientLocationPickerViewController {
						   	// Permission check for selection is only called upon selection, so we
						   	// can use this as a hook to pick the file if file selection is allowed
							locationPickerViewController.choose(item: item, location: item.location, cancelled: false)
						}
						return false
					}

					if let itemLocation = item.location, let navigationLocationFilter {
						return navigationLocationFilter(itemLocation, context)
					}
				}
				return true

			case .multiselection, .contextMenu, .leadingSwipe, .trailingSwipe, .drag, .acceptDrop, .search, .moreOptions, .addContent:
				return false
		}
	}

	// MARK: - Provide data source and initial view controller
	func provideDataSource(for location: OCLocation, maximumLevel: LocationLevel, context: ClientContext) -> OCDataSource? {
		var sectionDataSource: OCDataSource?

		let level = location.clientLocationLevel

		switch level {
			case .accounts, .account:
				sectionDataSource = OCDataSourceMapped(source: OCBookmarkManager.shared.bookmarksDatasource, creator: { [weak self] (_, bookmarkDataItem) in
					if let bookmark = bookmarkDataItem as? OCBookmark,
					   let self = self,
					   let rootContext = self.rootContext,
					   let accountControllerConfiguration = self.accountControllerConfiguration {
						if level == .account, bookmark.uuid != self.startLocation.bookmarkUUID {
							// If level is account, only return the start location's account (if provided)
							return nil
						}

						let controller = AccountController(bookmark: bookmark, context: rootContext, configuration: accountControllerConfiguration)
						controller.connect(completion: nil)

						return AccountControllerSection(with: controller)
					}

					return nil
				}, updater: nil, destroyer: { _, bookmarkItemRef, accountController in
					// Safely disconnect account controller if currently connected
					if let accountController = accountController as? AccountController {
						accountController.destroy() // needs to be called since AccountController keeps a reference to itself otherwise
					}
				}, queue: .main)

			case .drive, .folder: break
		}

		return sectionDataSource
	}

	deinit {
		personalDriveSubscription?.terminate()
	}

	/// Account used to list folders. A single saved account is enough when the
	/// picker was opened at the account chooser (auto upload) without a core.
	private func bookmarkForFolderListing(from location: OCLocation) -> OCBookmark? {
		if let bookmarkUUID = location.bookmarkUUID {
			return OCBookmarkManager.shared.bookmark(for: bookmarkUUID)
		}

		if location.clientLocationLevel == .accounts, OCBookmarkManager.shared.bookmarks.count == 1 {
			return OCBookmarkManager.shared.bookmarks.first
		}

		return nil
	}

	/// Puts the bookmark's live connection on the picker context so folder queries
	/// can run. Auto upload presents the sheet with only an originating view controller.
	private func attachConnection(for location: OCLocation, to context: ClientContext) {
		guard context.core == nil, let bookmark = bookmarkForFolderListing(from: location) else { return }

		let connection = AccountConnectionPool.shared.connection(for: bookmark)
		context.accountConnection = connection
		context.core = connection?.core

		guard connection?.core == nil, !didRequestConnection else { return }
		didRequestConnection = true

		connection?.connect { [weak self, weak context, weak connection] _ in
			OnMainThread {
				guard let self, let context else { return }
				context.core = connection?.core
				self.presentResolvedFolderListIfNeeded()
			}
		}
	}

	/// Location whose children should fill the sheet. `.accounts` with one account
	/// resolves to that account's root so the sheet lists folders instead of an
	/// empty account section.
	private func resolvedListingLocation(from location: OCLocation, in context: ClientContext) -> OCLocation? {
		var location = location

		if location.clientLocationLevel == .accounts {
			guard let bookmark = bookmarkForFolderListing(from: location) else { return nil }
			location = .account(bookmark)
		}

		switch location.clientLocationLevel {
			case .account, .drive, .folder:
				attachConnection(for: location, to: context)
			case .accounts:
				break
		}

		return folderLocationForListing(from: location, context: context)
	}

	/// Drive-based accounts have no folder query until the personal drive id exists.
	/// Keep watching and swap the sheet contents in once it does.
	private func watchForPersonalDriveIfNeeded() {
		guard personalDriveSubscription == nil,
		      !didPresentFolderList,
		      let core = rootContext?.core,
		      core.useDrives,
		      core.personalDrive == nil,
		      bookmarkForFolderListing(from: startLocation) != nil else { return }

		personalDriveSubscription = core.personalDriveDataSource.subscribe(updateHandler: { [weak self] subscription in
			let snapshot = subscription.snapshotResettingChangeTracking(false)
			guard let self, snapshot.numberOfItems > 0 else { return }

			for itemRef in snapshot.items {
				guard let record = try? core.personalDriveDataSource.record(forItemRef: itemRef),
				      let drive = record.item as? OCDrive else { continue }
				let driveID = drive.identifier
				guard !driveID.isEmpty else { continue }
				OnMainThread {
					self.resolvedPersonalDriveID = driveID
					self.presentResolvedFolderListIfNeeded()
				}
				return
			}
		}, on: .main, trackDifferences: false, performInitialUpdate: true)
	}

	private func presentResolvedFolderListIfNeeded() {
		guard !didPresentFolderList,
		      let rootContext,
		      let navigationController = rootNavigationController,
		      let folderLocation = resolvedListingLocation(from: startLocation, in: rootContext) else {
			watchForPersonalDriveIfNeeded()
			return
		}

		didPresentFolderList = true
		personalDriveSubscription?.terminate()
		personalDriveSubscription = nil

		let viewController = makeFolderListViewController(for: folderLocation, context: rootContext)
		applyListingTitle(to: viewController, location: folderLocation, context: rootContext)
		navigationController.setViewControllers([viewController], animated: false)
		navigationController.delegate?.navigationController?(navigationController, willShow: viewController, animated: false)
	}

	private func applyListingTitle(to viewController: UIViewController, location: OCLocation, context: ClientContext) {
		var title: String?

		switch location.clientLocationLevel {
			case .accounts:
				title = OCLocalizedString("Accounts", nil)
				viewController.cssSelector = .accountList

			case .account:
				title = OCLocalizedString("Account", nil)
				viewController.cssSelector = .accountList
				if let bookmarkUUID = location.bookmarkUUID {
					title = OCBookmarkManager.shared.bookmark(for: bookmarkUUID)?.displayName
				}

			case .drive:
				if let driveID = location.driveID {
					title = context.core?.drive(withIdentifier: driveID, attachedOnly: false)?.name
				}

			case .folder:
				title = location.lastPathComponent
		}

		if let title {
			viewController.navigationItem.titleLabelText = title
		}
	}

	private func folderLocationForListing(from location: OCLocation, context: ClientContext) -> OCLocation? {
		switch location.clientLocationLevel {
			case .drive, .folder:
				return location

			case .account:
				guard let core = context.core else { return nil }
				if core.useDrives {
					guard let driveID = location.driveID ?? context.drive?.identifier ?? core.personalDrive?.identifier ?? resolvedPersonalDriveID else {
						return nil
					}
					return .drive(driveID, bookmark: core.bookmark)
				}
				let root = OCLocation.legacyRoot
				root.bookmarkUUID = location.bookmarkUUID ?? core.bookmark.uuid
				return root

			case .accounts:
				return nil
		}
	}

	private func makeFolderListViewController(for location: OCLocation, context: ClientContext) -> UIViewController {
		let openLocation = OCLocation(bookmarkUUID: location.bookmarkUUID ?? context.core?.bookmark.uuid, driveID: location.driveID, path: location.path ?? "/")
		let query = OCQuery(for: openLocation)
		DisplaySettings.shared.updateQuery(withDisplaySettings: query)
		let folderContext = ClientContext(with: context, modifier: { context in
			context.itemLayout = .list
			if let driveID = openLocation.driveID, let core = context.core {
				context.drive = core.drive(withIdentifier: driveID, attachedOnly: false)
			}
		})

		let itemViewController = ClientItemViewController(context: folderContext, query: query, location: openLocation)
		itemViewController.cssSelectors = [.locationPicker, .collection]
		itemViewController.compressForKeyboard = false
		// ClientItemViewController starts the query. Starting it again here registers
		// a second item-list task against the same query and the sheet stays empty.
		return itemViewController
	}

	func provideViewController(for location: OCLocation, maximumLevel: LocationLevel, context: ClientContext) -> UIViewController? {
		var viewController: UIViewController?
		var presentedLocation = location

		if let folderLocation = resolvedListingLocation(from: location, in: context) {
			didPresentFolderList = true
			presentedLocation = folderLocation
			viewController = makeFolderListViewController(for: folderLocation, context: context)
		} else if let sectionDataSource = provideDataSource(for: location, maximumLevel: maximumLevel, context: context) {
			watchForPersonalDriveIfNeeded()
			let collectionViewController = CollectionViewController(context: context, sections: nil, useStackViewRoot: true, hierarchic: true)
			collectionViewController.compressForKeyboard = false
			collectionViewController.sectionsDataSource = sectionDataSource
			viewController = collectionViewController
		}

		if let viewController {
			applyListingTitle(to: viewController, location: presentedLocation, context: context)
			if presentedLocation.clientLocationLevel == .account, !(viewController is ClientItemViewController) {
				(viewController as? CollectionViewController)?.hideNavigationBar = true
			}
		}

		headerView?.secureView(core: context.core)

		return viewController
	}

	// MARK: - Presentation & Choice
	var rootNavigationController: UINavigationController?
	var rootViewController: UIViewController?
	var rootContext: ClientContext?

	public func pickerViewControllerForPresentation(with baseContext: ClientContext? = nil) -> UIViewController? {
		let navigationController = ThemeNavigationController()
		navigationController.cssSelector = .locationPicker

		// Set up navigation controller and context
		rootNavigationController = navigationController
		rootContext = ClientContext(with: baseContext, accountConnection: baseContext?.accountConnection, core: baseContext?.core, modifier: { context in
			if context.core == nil {
				context.core = baseContext?.accountConnection?.core
			}
			context.add(permissionHandler: { [weak self] context, dataItemRecord, checkInteraction, viewController in
				return self?.checkPermission(context: context, dataItemRecord: dataItemRecord, interaction: checkInteraction, viewController: viewController) ?? false
			})
			context.viewControllerPusher = self
			context.browserController = nil
			context.navigationRevocationHandler = nil
			context.navigationController = navigationController
			context.permissions = [ .selection ]
			context.itemLayout = .list
			context.itemStyler = { [weak self] (context, _, item) in
				if let item = item as? OCItem {
					if self?.allowFileSelection == false, item.type == .file {
						return .disabled
					}

					if let itemLocation = item.location,
					   let navigationLocationFilter = self?.navigationLocationFilter,
					   !navigationLocationFilter(itemLocation, context) {
						return .disabled
					}
				}
				return .regular
			}
		})

		// Compose view controller
		if let rootContext = rootContext {
			rootViewController = provideViewController(for: startLocation, maximumLevel: maximumLevel, context: rootContext)
			if let rootViewController {
				navigationController.pushViewController(rootViewController, animated: false)

				let pickerViewController = ClientLocationPickerViewController(with: self)
				pickerViewController.isModalInPresentation = true

				return pickerViewController

			}
		}

		return nil
	}

	public func present(in clientContext: ClientContext, baseContext: ClientContext? = nil) {
		// Compose and present view controller
		if let pickerViewController = pickerViewControllerForPresentation(with: baseContext) {
			clientContext.present(pickerViewController, animated: true)
		}
	}

	func choose(item: OCItem?, location: OCLocation?, context: ClientContext?, cancelled: Bool) {
		if let choiceHandler {
			self.choiceHandler = nil

			if !cancelled {
				// Add missing counterparts
				if let location, item == nil {
					// Add missing item for location
					if let core = context?.core {
						core.cachedItem(at: location, resultHandler: { error, item in
							if item?.bookmarkUUID == nil, let bookmarkUUID = location.bookmarkUUID?.uuidString {
								item?.bookmarkUUID = bookmarkUUID
							}
							OnMainThread {
								choiceHandler(item, location, context, cancelled)
							}
						})
						return
					}
				} else if let item, location == nil {
					// Add missing location for item
					if item.bookmarkUUID == nil, let bookmarkUUID = context?.core?.bookmark.uuid.uuidString {
						item.bookmarkUUID = bookmarkUUID
					}
					choiceHandler(item, item.location, context, cancelled)
					return
				}
			}

			choiceHandler(item, location, context, cancelled)
		}
	}
}

// MARK: - ViewControllerPusher
// Implemented solely to disable .compressForKeyboard for the collection views in the picker, as the usage of the keyboardLayoutGuide
// inexplicably leads to a bogus BottomBar layout when pushing the first "Files" view controller
extension ClientLocationPicker : ViewControllerPusher {
	public func pushViewController(context: ClientContext?, provider: (ClientContext) -> UIViewController?, push: Bool, animated: Bool) -> UIViewController? {
		if let context {
			let viewController = provider(context)

			if let collectionViewController = viewController as? CollectionViewController {
				// Disable .compressForKeyboard for CollectionViewController
				collectionViewController.compressForKeyboard = false
			}

			if push, let viewController {
				context.navigationController?.pushViewController(viewController, animated: animated)
			}

			return viewController
		}

		return nil
	}
}

extension ThemeCSSSelector {
	static let accountList = ThemeCSSSelector(rawValue: "accountList")
}
