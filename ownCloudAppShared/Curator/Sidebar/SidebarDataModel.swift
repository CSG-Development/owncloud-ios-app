import UIKit
import ownCloudSDK
import ownCloudApp

/// Owns the lifecycle of all SDK subscriptions and `AccountController` instances
/// for the sidebar. `ClientSidebarViewController` is a thin consumer of this model.
final class SidebarDataModel {

	// MARK: - Callbacks (always delivered on the main thread)

	/// Called when accounts or items have changed and the menu should be rebuilt.
	var onMenuNeedsReload: (() -> Void)?

	/// Called when the quota / available-space figures change.
	var onSpaceUpdated: ((_ used: Int64?, _ remaining: Int64?) -> Void)?

	/// Called when the primary bookmark changes (used to refresh the header view).
	var onBookmarkChanged: ((_ bookmark: OCBookmark?) -> Void)?

	/// Called when a connection closes so the VC can clear the footer quota display.
	var onConnectionClosed: (() -> Void)?

	// MARK: - Accessible state

	private(set) var accountControllersByBookmarkUUID: [UUID: AccountController] = [:]

	var accountControllers: [AccountController] {
		Array(accountControllersByBookmarkUUID.values)
	}

	func accountController(for bookmarkUUID: UUID) -> AccountController? {
		accountControllersByBookmarkUUID[bookmarkUUID]
	}

	// MARK: - Private

	private var accountsControllerSectionSource: OCDataSourceMapped?
	private var accountItemsSubscriptions: [UUID: OCDataSourceSubscription] = [:]
	private var bookmarksSubscription: OCDataSourceSubscription?
	private var statusNotificationObserver: NSObjectProtocol?
	private var connectionClosedGateResetAction: NavigationRevocationAction?
	private let updateAvailableSpaceGate = RunGate()

	// MARK: - Init / deinit

	init(clientContext: ClientContext, controllerConfiguration: AccountController.Configuration) {
		accountsControllerSectionSource = OCDataSourceMapped(
			source: nil,
			creator: { [weak self] _, bookmarkDataItem in
				guard let bookmark = bookmarkDataItem as? OCBookmark, let self else { return nil }

				let controller = AccountController(
					bookmark: bookmark,
					context: clientContext,
					configuration: controllerConfiguration
				)
				self.accountControllersByBookmarkUUID[bookmark.uuid] = controller
				self.onBookmarkChanged?(bookmark)
				self.subscribeToAccountItems(for: controller)

				DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
					self?.onMenuNeedsReload?()
				}

				return controller
			},
			updater: nil,
			destroyer: { [weak self] _, _, mappedItem in
				guard let accountController = mappedItem as? AccountController,
					  let bookmarkUUID = accountController.bookmark?.uuid else { return }
				self?.accountItemsSubscriptions[bookmarkUUID]?.terminate()
				self?.accountItemsSubscriptions.removeValue(forKey: bookmarkUUID)
				self?.accountControllersByBookmarkUUID.removeValue(forKey: bookmarkUUID)
				accountController.destroy()
			},
			queue: .main
		)

		accountsControllerSectionSource?.trackItemVersions = true

		bookmarksSubscription = OCBookmarkManager.shared.bookmarksDatasource.subscribe(
			updateHandler: { [weak self] _ in
				DispatchQueue.main.async {
					self?.onBookmarkChanged?(OCBookmarkManager.shared.bookmarks.first)
					self?.onMenuNeedsReload?()
				}
			},
			on: nil,
			trackDifferences: false,
			performInitialUpdate: false
		)

		statusNotificationObserver = NotificationCenter.default.addObserver(
			forName: AccountConnection.StatusChangedNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.onMenuNeedsReload?()
		}

		installConnectionClosedGateResetAction()

		// Connect the source last; callbacks are already wired by the VC after init.
		accountsControllerSectionSource?.source = OCBookmarkManager.shared.bookmarksDatasource

		OnMainThread {
			OnMainThread(after: 1) { [weak self] in
				guard let self else { return }
				if self.accountControllersByBookmarkUUID.isEmpty,
				   !OCBookmarkManager.shared.bookmarks.isEmpty {
					self.forceReloadBookmarks()
				}
			}
		}
	}

	deinit {
		accountsControllerSectionSource?.source = nil
		accountItemsSubscriptions.values.forEach { $0.terminate() }
		bookmarksSubscription?.terminate()
		connectionClosedGateResetAction?.unregister(globally: true)
		if let observer = statusNotificationObserver {
			NotificationCenter.default.removeObserver(observer)
		}
	}

	// MARK: - Private helpers

	private func subscribeToAccountItems(for accountController: AccountController) {
		guard let bookmarkUUID = accountController.bookmark?.uuid else { return }
		accountItemsSubscriptions[bookmarkUUID]?.terminate()
		accountItemsSubscriptions[bookmarkUUID] = accountController.itemsDataSource.subscribe(
			updateHandler: { [weak self] _ in
				DispatchQueue.main.async { self?.onMenuNeedsReload?() }
			},
			on: .main,
			trackDifferences: false,
			performInitialUpdate: false
		)
	}

	private func installConnectionClosedGateResetAction() {
		connectionClosedGateResetAction?.unregister(globally: true)

		let action = NavigationRevocationAction(
			eventMatcher: { event in
				if case .connectionClosed = event { return true }
				return false
			},
			action: { [weak self] _, _ in
				self?.updateAvailableSpaceGate.reset()
				self?.onConnectionClosed?()
				self?.installConnectionClosedGateResetAction()
			}
		)

		connectionClosedGateResetAction = action
		action.register(globally: true)
	}

	// MARK: - Public API

	func forceReloadBookmarks() {
		guard let bookmarks = OCBookmarkManager.shared.bookmarks as? [OCDataItem & OCDataItemVersioning] else { return }
		(OCBookmarkManager.shared.bookmarksDatasource as? OCDataSourceArray)?.setVersionedItems(bookmarks)
		onMenuNeedsReload?()
	}

	func updateAvailableSpace(focusedBookmark: OCBookmark?) {
		updateAvailableSpaceGate.runIfIdle { [weak self] done in
			guard let bookmark = focusedBookmark ?? OCBookmarkManager.shared.bookmarks.first,
				  let core = AccountConnectionPool.shared.connection(for: bookmark)?.core
			else {
				DispatchQueue.main.async { self?.onSpaceUpdated?(nil, nil) }
				done()
				return
			}
			DispatchQueue.main.async {
				self?.onSpaceUpdated?(
					core.rootQuotaBytesUsed?.int64Value,
					core.rootQuotaBytesRemaining?.int64Value
				)
			}
			done()
		}
	}
}
