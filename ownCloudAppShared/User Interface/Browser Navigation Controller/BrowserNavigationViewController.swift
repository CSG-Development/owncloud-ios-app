//
//  BrowserNavigationViewController.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 16.01.23.
//  Copyright © 2023 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2023, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import SnapKit
import UIKit
import ownCloudSDK

public protocol BrowserNavigationViewControllerDelegate: AnyObject {
	func browserNavigation(
		viewController: BrowserNavigationViewController,
		contentViewControllerDidChange: UIViewController?)
}

open class BrowserNavigationViewController: EmbeddingViewController, Themeable, BrowserNavigationHistoryDelegate, ThemeCSSAutoSelector {
	lazy var contentContainerView: UIView = {
		let view = UIView()
		view.cssSelector = .content
		view.focusGroupIdentifier = "com.owncloud.content"
		return view
	}()

	lazy var wrappedContentContainerView: UIView = {
		contentContainerView.withScreenshotProtection
	}()

	lazy var navigationView: UINavigationBar = {
		let navigationView = UINavigationBar()
		navigationView.delegate = self
		return navigationView
	}()

	lazy var contentContainerLidView: UIView = {
		let view = UIView()
		view.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
		view.isHidden = true
		view.addGestureRecognizer(UITapGestureRecognizer(
			target: self,
			action: #selector(showHideSideBar)
		))
		return view
	}()

	private var isTabBarHidden: Bool = false
	var tabBarView = HCBrowserNavigationTabBarView()
	var sideBarSeperatorView: ThemeCSSView = ThemeCSSView(withSelectors: [.separator])

	lazy open var history: BrowserNavigationHistory = {
		let history = BrowserNavigationHistory()
		history.delegate = self
		return history
	}()

	weak open var delegate: BrowserNavigationViewControllerDelegate?
	open var clientContextProvider: (() -> ClientContext?)?
	open var accountControllerProvider: ((UUID) -> AccountController?)?

	open override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()

		if let windowWidth = view.window?.bounds.width {
			if preferredSideBarWidth > windowWidth {
				// Adapt to widths slimmer than sidebarWidth
				sideBarWidth = windowWidth - 20
			} else {
				// Use preferredSideBarWidth
				sideBarWidth = preferredSideBarWidth
			}

			if windowWidth < sideBarWidth * 2.5 {
				// Slide the sidebar over the content if the content doesn't have at least 2.5x the space of the sidebar
				sideBarDisplayMode = .over
			} else {
				// Show sidebar and content side by side if there's enough space
				sideBarDisplayMode = .sideBySide
			}
		} else {
			// Slide the sidebar over the content
			// if the window width can't be determined
			sideBarDisplayMode = .over
		}
		setContainerLidHidden(isSideBarHidden || effectiveSideBarDisplayMode != .over)
	}

	open override func viewDidLoad() {
		super.viewDidLoad()

		contentContainerView.addSubview(navigationView)

		view.addSubview(wrappedContentContainerView)
		view.addSubview(sideBarSeperatorView)
		view.addSubview(tabBarView)
		view.addSubview(contentContainerLidView)

		contentContainerLidView.snp.remakeConstraints {
			$0.edges.equalToSuperview()
		}

		sideBarSeperatorView.snp.remakeConstraints {
			$0.top.bottom.equalToSuperview()
			$0.leading.equalToSuperview().offset(-1)
			$0.width.equalTo(1)
		}

		updateDynamicLayout()
		setupTabBar()

		navigationView.items = []
	}

	private func updateDynamicLayout() {
		guard let sidebarView, let view, sidebarView.superview != nil else { return }

		sidebarView.snp.remakeConstraints {
			guard !isSideBarHidden else {
				$0.trailing.equalTo(view.snp.leading)
				$0.top.equalToSuperview()
				if UIDevice.current.isIpad {
					$0.bottom.equalTo(tabBarView.snp.top)
				} else {
					$0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
				}
				$0.width.equalTo(sideBarWidth)
				return
			}

			switch effectiveSideBarDisplayMode {
				case .fullWidth:
					$0.leading.trailing.top.equalToSuperview()
					$0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)

				case .sideBySide, .over:
					$0.leading.top.equalToSuperview()
					$0.width.equalTo(sideBarWidth)
					if UIDevice.current.isIpad {
						$0.bottom.equalTo(tabBarView.snp.top)
					} else {
						$0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
					}
			}
		}

		tabBarView.snp.remakeConstraints {
			if isTabBarHidden {
				$0.top.equalTo(view.snp.bottom)
			} else {
				$0.top.equalTo(wrappedContentContainerView.snp.bottom)
				$0.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
			}
			$0.leading.equalTo(view.snp.leading).priority(.high)
			$0.trailing.equalTo(view.snp.trailing)
			$0.height.equalTo(68)
		}

		wrappedContentContainerView.snp.remakeConstraints {
			guard !isSideBarHidden else {
				$0.top.leading.trailing.equalToSuperview()
				return
			}
			switch effectiveSideBarDisplayMode {
				case .fullWidth:
					$0.top.leading.trailing.equalToSuperview()

				case .sideBySide:
					$0.top.trailing.equalToSuperview()
					$0.leading.equalTo(sidebarView.snp.trailing).offset(-1)

				case .over:
					$0.top.trailing.equalToSuperview()
					$0.leading.equalTo(view.snp.leading)
			}
		}
	}

	private func setupTabBar() {
		tabBarView.onTabSelected = { [weak self] tab in
			guard
				let self,
			    let tab
			else { return }

			let connection = AccountConnectionPool.shared.connectionsByBookmarkUUID.values.first!
			guard let clientContext = clientContextProvider?() else { return }
			let context = ClientContext(with: clientContext, accountConnection: connection)

			guard
				let bookmarkUUID = connection.core?.bookmark.uuid,
				let accountController = accountControllerProvider?(bookmarkUUID)
			else { return }

			switch tab {
				case .files:
					let location = OCLocation(
						bookmarkUUID: bookmarkUUID,
						driveID: nil,
						path: "/"
					)
					_ = location.openItem(
						from: self,
						with: context,
						animated: true,
						pushViewController: true
					) { _ in }

				case .links:
					let item = CollectionSidebarAction(
						with: "", icon: nil,
						viewControllerProvider: { (context, action) in
							accountController.provideViewController(for: .sharedByLink, in: context)
						},
						cacheViewControllers: false
					)

					_ = item.openItem(
						from: self,
						with: context,
						animated: true,
						pushViewController: true
					) { _ in }

				case .uploads:
					let item = CollectionSidebarAction(
						with: "", icon: nil,
						viewControllerProvider: { (context, action) in
							accountController.provideViewController(for: .activity, in: context)
						}, cacheViewControllers: false)

					_ = item.openItem(
						from: self,
						with: context,
						animated: true,
						pushViewController: true
					) { _ in }

				case .offline:
					let item = CollectionSidebarAction(
						with: "", icon: nil,
						viewControllerProvider: { (context, action) in
							accountController.provideViewController(for: .availableOfflineItems, in: context)
						}, cacheViewControllers: false)

					_ = item.openItem(
						from: self,
						with: context,
						animated: true,
						pushViewController: true
					) { _ in }
			}
		}
	}

	func updateBottomNavigation() {
		//tabBarButtons.forEach { $0.isSelected = false }
		//if let item = history.lastPushAttempt.navigationBookmark?.specialItem
	}

	private var _themeRegistered = false
	open override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if !_themeRegistered {
			_themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	open override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		navigationController?.isNavigationBarHidden = true

		setNavigationBarHidden(false, animated: false)
	}

	// MARK: - Navigation Bar
	open func setNavigationBarHidden(
		_ hidden: Bool,
		animated: Bool,
		completion: (() -> Void)? = nil
	) {
		let updateLayout = {
			self.navigationView.snp.remakeConstraints {
				$0.leading.trailing.equalTo(self.contentContainerView.safeAreaLayoutGuide)
				if hidden {
					$0.bottom.equalTo(self.contentContainerView.snp.top)
				} else {
					$0.top.equalTo(self.contentContainerView.safeAreaLayoutGuide.snp.top)
				}
			}
		}

		OnMainThread(inline: true) {
			if animated {
				UIView.animate(
					withDuration: 0.3,
					animations: {
						updateLayout()
						self.view.layoutIfNeeded()
					},
					completion: { _ in
						completion?()
					})
			} else {
				updateLayout()
				completion?()
			}
		}
	}

	// MARK: - Push & Navigation
	open func push(
		viewController: UIViewController,
		completion: BrowserNavigationHistory.CompletionHandler? = nil
	) {
		push(item: BrowserNavigationItem(viewController: viewController), completion: completion)
	}

	open func deleteCurrent(
		completion: BrowserNavigationHistory.CompletionHandler? = nil
	) {
		history.deleteCurrent(completion: completion)
	}

	open func push(
		item: BrowserNavigationItem, completion: BrowserNavigationHistory.CompletionHandler? = nil
	) {
		// Push to history (+ present)
		history.push(item: item)

		if hideSideBarInOverDisplayModeOnPush, sideBarDisplayMode == .over {
			setSideBarHidden(true, animated: true)
		}
	}

	open func moveBack(completion: BrowserNavigationHistory.CompletionHandler? = nil) {
		history.moveBack(completion: completion)
	}

	open func moveForward(completion: BrowserNavigationHistory.CompletionHandler? = nil) {
		history.moveForward(completion: completion)
	}

	// MARK: - View Controller presentation
	open override func addContentViewControllerSubview(_ contentViewControllerView: UIView) {
		contentContainerView.insertSubview(contentViewControllerView, at: 0)
	}

	open override func constraintsForEmbedding(contentViewController: UIViewController)
		-> [NSLayoutConstraint] {
		if let contentView = contentViewController.view {
			return [
				contentView.topAnchor.constraint(equalTo: navigationView.bottomAnchor),
				contentView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
				contentView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
				contentView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor)
			]
		}

		return []
	}

	@objc func showHideSideBar() {
		setSideBarHidden(!isSideBarHidden)

	}

	@objc func navBack() {
		moveBack()
	}

	@objc func navForward() {
		moveForward()
	}

	func buildSideBarToggleBarButtonItem() -> UIBarButtonItem {
		let buttonItem = UIBarButtonItem(
			image: OCItem.hanurgerMenu, style: .plain, target: self,
			action: #selector(showHideSideBar))
		buttonItem.tag = BarButtonTags.showHideSideBar.rawValue
		buttonItem.accessibilityLabel = OCLocalizedString("Show/Hide sidebar", nil)
		return buttonItem
	}

	private enum BarButtonTags: Int {
		case mask = 0xC0FFEE0
		case showHideSideBar
		case backButton
		case forwardButton
	}

	func updateLeftBarButtonItems(
		for navigationItem: UINavigationItem, withToggleSideBar: Bool = false,
		withBackButton: Bool = false, withForwardButton: Bool = false
	) {
		let (_, existingItems) = navigationItem.navigationContent.items(
			withIdentifier: "browser-navigation-left")

		func reuseOrBuild(_ tag: BarButtonTags, _ build: () -> UIBarButtonItem) -> UIBarButtonItem {
			for barButtonItem in existingItems {
				if barButtonItem.tag == tag.rawValue {
					return barButtonItem
				}
			}

			return build()
		}

		var leadingButtons: [UIBarButtonItem] = []
		var sidebarButtons: [UIBarButtonItem] = []

		if withToggleSideBar {
			let item = reuseOrBuild(
				.showHideSideBar,
				{
					return buildSideBarToggleBarButtonItem()
				})

			sidebarButtons.append(item)
		}

		if withBackButton {
			let item = reuseOrBuild(
				.backButton,
				{
					let backButtonItem = UIBarButtonItem(
						image: OCSymbol.icon(forSymbolName: "chevron.backward"), style: .plain,
						target: self, action: #selector(navBack))
					backButtonItem.tag = BarButtonTags.backButton.rawValue

					return backButtonItem
				})

			item.isEnabled = history.canMoveBack

			leadingButtons.append(item)
		}

		if withForwardButton {
			let item = reuseOrBuild(
				.forwardButton,
				{
					let forwardButtonItem = UIBarButtonItem(
						image: OCSymbol.icon(forSymbolName: "chevron.forward"), style: .plain,
						target: self, action: #selector(navForward))
					forwardButtonItem.tag = BarButtonTags.forwardButton.rawValue

					return forwardButtonItem
				})

			item.isEnabled = history.canMoveForward

			leadingButtons.append(item)
		}

		let sideBarItem = NavigationContentItem(
			identifier: "browser-navigation-left", area: .left, priority: .standard,
			position: .leading, items: sidebarButtons)
		sideBarItem.visibleInPriorities = [.standard, .high, .highest]

		navigationItem.navigationContent.add(items: [
			sideBarItem,
			NavigationContentItem(
				identifier: "browser-navigation-left", area: .left, priority: .standard,
				position: .leading, items: leadingButtons)
		])
	}

	func updateContentNavigationItems() {
		let hasNavigation = !(history.lastPushAttempt?.isSpecialTabBarItem ?? false)

		if let contentNavigationItem = contentViewController?.navigationItem {
			updateLeftBarButtonItems(
				for: contentNavigationItem,
				withToggleSideBar: (effectiveSideBarDisplayMode == .sideBySide)
				? isSideBarHidden : true, withBackButton: hasNavigation, withForwardButton: hasNavigation)
		}

		updateSideBarNavigationItem()
	}

	// MARK: - BrowserNavigationHistoryDelegate

	public func updateNavigation() {
		if let navigationItem = contentViewController?.navigationItem {
			updateContentNavigationItems()

			navigationView.items = [ navigationItem ]
		}
	}

	public func present(
		item: BrowserNavigationItem?, with direction: BrowserNavigationHistory.Direction,
		completion: BrowserNavigationHistory.CompletionHandler?
	) {
		let needsSideBarLayout =
			(((item != nil) && (contentViewController == nil))
				|| ((item == nil) && (contentViewController != nil)))
			&& (emptyHistoryBehaviour == .expandSideBarToFullWidth)

		if let item {
			// Has content
			let itemViewController = item.viewController

			contentViewController = itemViewController

			if let navigationItem = itemViewController?.navigationItem {
				updateContentNavigationItems()

				navigationView.items = [navigationItem]
			}
		} else {
			// Has no content
			contentViewController = nil
		}

		self.view.layoutIfNeeded()

		let done = {
			self.delegate?.browserNavigation(
				viewController: self, contentViewControllerDidChange: self.contentViewController)
			completion?(true)
		}

		if needsSideBarLayout {
			OnMainThread {
				UIView.animate(
					withDuration: 0.3,
					animations: {
						self.updateSideBarLayoutAndAppearance()
						self.view.layoutIfNeeded()
					},
					completion: { _ in
						done()
					})
			}
		} else {
			done()
		}
	}

	// MARK: - Sidebar View Controller
	func updateSideBarNavigationItem() {
		var sideBarNavigationItem: UINavigationItem?

		if let sidebarViewController {
			// Add show/hide sidebar button to sidebar left items
			if let navigationController = sidebarViewController as? UINavigationController {
				sideBarNavigationItem = navigationController.topViewController?.navigationItem
			} else {
				sideBarNavigationItem = sidebarViewController.navigationItem
			}
		}

		if let sideBarNavigationItem {
			updateLeftBarButtonItems(
				for: sideBarNavigationItem,
				withToggleSideBar: (effectiveSideBarDisplayMode != .fullWidth))
		}
	}

	var sidebarView: UIView?

	open var sidebarViewController: UIViewController? {
		willSet {
			sidebarViewController?.willMove(toParent: nil)
			sidebarViewController?.view.removeFromSuperview()
			sidebarViewController?.removeFromParent()
		}
		didSet {
			if let sidebarViewController, let sidebarViewControllerView = sidebarViewController.view {
				sidebarViewController.focusGroupIdentifier = "com.owncloud.sidebar"

				updateSideBarNavigationItem()
				sidebarView = sidebarViewControllerView
				addChild(sidebarViewController)
				view.addSubview(sidebarViewControllerView)
				sidebarViewControllerView.translatesAutoresizingMaskIntoConstraints = false
				updateSideBarLayoutAndAppearance()
				sidebarViewController.didMove(toParent: self)
			} else {
				updateSideBarLayoutAndAppearance()
			}
		}
	}

	// MARK: - Constraints, state & animation

	public enum SideBarDisplayMode {
		case fullWidth
		case sideBySide
		case over
	}

	public enum EmptyHistoryBehaviour {
		case none
		case expandSideBarToFullWidth
		case showEmptyHistoryViewController
	}

	public var isSideBarHidden: Bool = false {
		didSet {
			setNeedsStatusBarAppearanceUpdate()
		}
	}
	public var preferredSideBarWidth: CGFloat = 320
	var sideBarWidth: CGFloat = 320
	var preferredSideBarDisplayMode: SideBarDisplayMode?
	var sideBarDisplayMode: SideBarDisplayMode = .over {
		didSet {
			updateSideBarLayoutAndAppearance()
		}
	}

	var effectiveSideBarDisplayMode: SideBarDisplayMode {
		if history.isEmpty, emptyHistoryBehaviour == .expandSideBarToFullWidth {
			return .fullWidth
		}

		return sideBarDisplayMode
	}

	public var emptyHistoryBehaviour: EmptyHistoryBehaviour = .expandSideBarToFullWidth
	public var hideSideBarInOverDisplayModeOnPush: Bool = true

	func setTabBarHidden(_ isHidden: Bool, animated: Bool = true) {
		let animations = {
			self.updateDynamicLayout()
			self.view.layoutIfNeeded()
		}

		let completion: (Bool) -> Void = { _ in

		}

		updateDynamicLayout()
		self.isTabBarHidden = isHidden
		if animated {
			UIView.animate(withDuration: 0.3, animations: animations, completion: completion)
		} else {
			animations()
			completion(true)
		}
	}

	func setContainerLidHidden(_ isHidden: Bool, animated: Bool = true) {
		let animations = {
			self.contentContainerLidView.alpha = isHidden ? 0.0 : 1.0
		}

		let completion: (Bool) -> Void = { _ in
			self.contentContainerLidView.isHidden = isHidden
		}

		self.contentContainerLidView.alpha = isHidden ? 1.0 : 0.0
		if !isHidden {
			self.contentContainerLidView.isHidden = false
		}

		if animated {
			UIView.animate(withDuration: 0.3, animations: animations, completion: completion)
		} else {
			animations()
			completion(true)
		}
	}

	open func setSideBarHidden(_ isHidden: Bool, animated: Bool = true) {
		let animations = {
			self.updateSideBarLayoutAndAppearance()
			self.sidebarViewController?.view.layoutIfNeeded()
			self.view.layoutIfNeeded()
		}

		let completion: (Bool) -> Void = { _ in

		}
		self.updateSideBarLayoutAndAppearance()
		self.isSideBarHidden = isHidden
		if animated {
			UIView.animate(withDuration: 0.3, animations: animations, completion: completion)
		} else {
			animations()
			completion(true)
		}
	}

	func updateSideBarLayoutAndAppearance() {
		updateDynamicLayout()

		updateContentNavigationItems()
	}

	// MARK: - Themeing
	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		navigationView.applyThemeCollection(collection)
		view.apply(css: collection.css, properties: [.fill])
	}

	public var cssAutoSelectors: [ThemeCSSSelector] = [.splitView]

	// MARK: - Status Bar style
	open override var preferredStatusBarStyle: UIStatusBarStyle {
		var statusBarStyle: UIStatusBarStyle?

		if !isSideBarHidden, let sidebarViewController {
			statusBarStyle = Theme.shared.activeCollection.css.getStatusBarStyle(
				for: sidebarViewController)
		} else if let contentViewController {
			statusBarStyle = Theme.shared.activeCollection.css.getStatusBarStyle(
				for: contentViewController)
		}

		if statusBarStyle == nil {
			statusBarStyle = Theme.shared.activeCollection.css.getStatusBarStyle(for: self)
		}

		return statusBarStyle ?? super.preferredStatusBarStyle
	}

	open override var childForStatusBarStyle: UIViewController? {
		nil
	}

	open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		let isPhone = traitCollection.userInterfaceIdiom == .phone
		let isLandscape = traitCollection.verticalSizeClass == .compact

		if isLandscape && isPhone {
			setTabBarHidden(true)
		} else {
			setTabBarHidden(false)
		}
	}

	func notifyScroll(_ direction: HCScrollDirectionProcessor.ScrollDirection) {
		let isPhone = traitCollection.userInterfaceIdiom == .phone
		let isLandscape = traitCollection.verticalSizeClass == .compact

		guard isPhone && isLandscape else { return }

		switch direction {
			case .down:
				setTabBarHidden(true)
			case .up:
				setTabBarHidden(false)
			case .none:
				break
		}
	}
}

extension BrowserNavigationViewController: UINavigationBarDelegate {
	public func position(for bar: UIBarPositioning) -> UIBarPosition {
		.topAttached
	}
}

extension UIViewController {
	public var browserNavigationViewController: BrowserNavigationViewController? {
		var viewController: UIViewController? = self
		while viewController != nil {
			if let browserNavigationViewController = viewController as? BrowserNavigationViewController {
				return browserNavigationViewController
			}
			viewController = viewController?.parent
		}
		return nil
	}
}
