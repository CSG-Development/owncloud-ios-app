//
//  ClientLocationPickerViewController.swift
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

class ClientLocationPickerViewController: EmbeddingViewController, CustomViewControllerEmbedding, Themeable, UINavigationControllerDelegate {
	var locationPicker: ClientLocationPicker

	init(with locationPicker: ClientLocationPicker) {
		self.locationPicker = locationPicker
		super.init(nibName: nil, bundle: nil)
		self.locationPicker.rootNavigationController?.delegate = self

		self.cssSelector = .locationPicker

		currentLocation = (self.locationPicker.rootNavigationController?.topViewController as? FileBrowserContent)?.location
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	var bottomButtonBar: BottomButtonBar?
	var topSeparatorLine: UIView = ThemeCSSView(withSelectors: [.separator])
	private let contentContainerView = UIView()

	override func viewDidLoad() {
		super.viewDidLoad()

		let showCancelButton = locationPicker.headerView != nil

		bottomButtonBar = BottomButtonBar(prompt: locationPicker.selectPrompt, selectButtonTitle: locationPicker.selectButtonTitle, cancelButtonTitle: OCLocalizedString("Cancel", nil), hasCancelButton: showCancelButton, selectAction: UIAction(handler: { [weak self] _ in
			self?.chooseCurrentLocation()
		}), cancelAction: UIAction(handler: { [weak self] _ in
			self?.cancel()
		}))

		topSeparatorLine.translatesAutoresizingMaskIntoConstraints = false
		contentContainerView.translatesAutoresizingMaskIntoConstraints = false
		contentContainerView.setContentHuggingPriority(.defaultLow, for: .vertical)
		contentContainerView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

		guard let bottomButtonBar else { return }

		view.addSubview(contentContainerView)
		view.addSubview(bottomButtonBar)

		var constraints: [NSLayoutConstraint] = [
			contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			contentContainerView.bottomAnchor.constraint(equalTo: bottomButtonBar.topAnchor),
			contentContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).with(priority: .defaultHigh),

			bottomButtonBar.leftAnchor.constraint(equalTo: view.leftAnchor),
			bottomButtonBar.rightAnchor.constraint(equalTo: view.rightAnchor),
			bottomButtonBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		]

		if let headerView = locationPicker.headerView {
			headerView.translatesAutoresizingMaskIntoConstraints = false
			headerView.setContentHuggingPriority(.required, for: .vertical)
			headerView.setContentCompressionResistancePriority(.required, for: .vertical)
			headerView.cssSelectors = [.header]
			view.addSubview(headerView)
			headerView.addSubview(topSeparatorLine)

			constraints.append(contentsOf: [
				headerView.leftAnchor.constraint(equalTo: view.leftAnchor),
				headerView.rightAnchor.constraint(equalTo: view.rightAnchor),
				headerView.topAnchor.constraint(equalTo: view.topAnchor),
				contentContainerView.topAnchor.constraint(equalTo: headerView.bottomAnchor),

				topSeparatorLine.leftAnchor.constraint(equalTo: headerView.leftAnchor),
				topSeparatorLine.rightAnchor.constraint(equalTo: headerView.rightAnchor),
				topSeparatorLine.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
				topSeparatorLine.heightAnchor.constraint(equalToConstant: 1)
			])
		} else {
			constraints.append(contentContainerView.topAnchor.constraint(equalTo: view.topAnchor))
		}

		NSLayoutConstraint.activate(constraints)

		contentViewController = locationPicker.rootNavigationController
	}

	override func addContentViewControllerSubview(_ contentViewControllerView: UIView) {
		contentContainerView.addSubview(contentViewControllerView)
	}

	private var registered = false
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if !registered {
			registered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
		startVisibleQueryIfNeeded()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		startVisibleQueryIfNeeded()
	}

	private func startVisibleQueryIfNeeded() {
		guard let fileBrowser = locationPicker.rootNavigationController?.topViewController as? FileBrowserContent,
		      let query = fileBrowser.query,
		      query.state == .stopped else { return }
		fileBrowser.clientContext?.core?.start(query)
	}

	// MARK: - UINavigationControllerDelegate
	func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
		var rightBarButtonItems: [UIBarButtonItem] = []

		if locationPicker.headerView == nil {
			// Add cancel button to navigation bar if no headerView is used
			rightBarButtonItems.append(UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction(handler: { [weak self] (_) in
				self?.choose(cancelled: true)
			})))
		}

		if let fileBrowser = viewController as? FileBrowserContent, let location = fileBrowser.location {
			currentLocationContext = fileBrowser.clientContext
			if let query = fileBrowser.query, query.state == .stopped {
				fileBrowser.clientContext?.core?.start(query)
			}

			if let bookmark = fileBrowser.clientContext?.core?.bookmark, location.bookmarkUUID == nil {
				// Add bookmark UUID to location
				currentLocation = OCLocation(bookmarkUUID: bookmark.uuid, driveID: location.driveID, path: location.path)
			} else {
				currentLocation = location
			}

			// Add actions for location
			if let currentLocation, let currentLocationContext {
				var rootItem = currentLocationContext.rootItem as? OCItem
				if rootItem == nil {
					rootItem = try? currentLocationContext.core?.cachedItem(at: currentLocation)
				}

				if let rootItem, let core = currentLocationContext.core {
					let actionsLocation = OCExtensionLocation(ofType: .action, identifier: .locationPickerBar)
					let actionContext = ActionContext(viewController: viewController, clientContext: currentLocationContext, core: core, query: currentLocationContext.query, items: [rootItem], location: actionsLocation, sender: self)
					let actions = Action.sortedApplicableActions(for: actionContext)

					for action in actions {
						rightBarButtonItems.append(action.provideBarButtonItem())
					}
				}
			}
		} else {
			currentLocation = nil
			currentLocationContext = nil
		}

		viewController.navigationItem.navigationContent.add(items: [
			NavigationContentItem(identifier: "location-picker-actions-right", area: .right, priority: .high, position: .trailing, items: rightBarButtonItems)
		])
	}

	// MARK: - Location tracking and choice
	var currentLocationContext: ClientContext? // context in which to see currentLocation
	var currentLocation: OCLocation? {
		didSet {
			var validTargetLocation: Bool = false

			if let currentLocation {
				if let allowedLocationFilter = locationPicker.allowedLocationFilter {
					validTargetLocation = allowedLocationFilter(currentLocation, currentLocationContext)
				} else {
					validTargetLocation = true
				}
			}

			bottomButtonBar?.selectButton.isEnabled = validTargetLocation
		}
	}

	@objc func chooseCurrentLocation() {
		choose(location: currentLocation, cancelled: false)
	}

	@objc func cancel() {
		choose(cancelled: true)
	}

	func choose(item: OCItem? = nil, location: OCLocation? = nil, cancelled: Bool) {
		let context = currentLocationContext
		dismiss(animated: true) { [weak self] in
			self?.locationPicker.choose(item: item, location: location, context: context, cancelled: cancelled)
		}
	}

	// MARK: - CustomViewControllerEmbedding
	func constraintsForEmbedding(contentView: UIView) -> [NSLayoutConstraint] {
		return contentContainerView.embed(toFillWith: contentView)
	}

	// MARK: - Themeable
	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		let collectionBackground = collection.css.getColor(.fill, selectors: [.locationPicker, .collection], for: contentContainerView) ?? HCColor.Structure.appBackground(collection.isDark)
		let chromeBackground = collection.css.getColor(.fill, selectors: [.locationPicker, .header], for: locationPicker.headerView) ?? HCColor.Structure.menuBackground(collection.isDark)

		view.backgroundColor = collectionBackground
		contentContainerView.backgroundColor = collectionBackground
		locationPicker.headerView?.backgroundColor = chromeBackground
		bottomButtonBar?.backgroundColor = collection.css.getColor(.fill, selectors: [.locationPicker, .bottomButtonBar], for: bottomButtonBar) ?? chromeBackground
	}
}

extension ThemeCSSSelector {
	static let locationPicker = ThemeCSSSelector(rawValue: "locationPicker")
}
