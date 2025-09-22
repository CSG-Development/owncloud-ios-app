//
//  ClientLocationBarController.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 23.01.23.
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

import UIKit
import ownCloudSDK

extension ThemeCSSSelector {
	static let locationBar = ThemeCSSSelector(rawValue: "locationBar")
}

open class ClientLocationBarController: UIViewController, Themeable {
	public var location: OCLocation? {
		didSet {
			updateView()
		}
	}
	public var clientContext: ClientContext? {
		didSet {
			updateView()
		}
	}

	public lazy var segmentView: SegmentView = {
		let view = SegmentView(
			with: [],
			truncationMode: .truncateTail,
			scrollable: true,
			limitVerticalSpaceUsage: true
		)
		view.itemSpacing = 0
		return view
	}()

	public init() {
		super.init(nibName: nil, bundle: nil)
	}

	required public init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	open override func loadView() {
		view = ThemeCSSView(withSelectors: [.toolbar, .locationBar])
		view.focusGroupIdentifier = "com.owncloud.location-bar"
	}

	open override func viewDidLoad() {
		super.viewDidLoad()

		view.addSubview(segmentView)
		segmentView.snp.makeConstraints { $0.edges.equalToSuperview() }

		updateView()
	}

	var _themeRegistered: Bool = false
	open override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if !_themeRegistered {
			_themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func composeSegments(location: OCLocation?, in clientContext: ClientContext) -> [SegmentViewItem] {
		guard let location else {
			return []
		}
		return OCLocation.composeSegments(breadcrumbs: location.breadcrumbs(in: clientContext), in: clientContext, segmentConfigurator: { breadcrumb, segment in
			// Make breadcrumbs tappable using the provided action's .actionBlock
			if breadcrumb.actionBlock != nil {
				segment.gestureRecognizers = [
					ActionTapGestureRecognizer(action: { [weak self] _ in
						if let clientContext = self?.clientContext {
							breadcrumb.run(options: [.clientContext : clientContext])
						}
					})
				]
				segment.isAccessibilityElement = true
				segment.accessibilityTraits = .button
			}
		})
	}

	private func updateView() {
		guard let clientContext else { return }

		segmentView.items = composeSegments(location: location, in: clientContext)
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {

	}
}
