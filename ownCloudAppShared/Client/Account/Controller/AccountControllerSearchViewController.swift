//
//  AccountControllerSearchViewController.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 17.01.24.
//  Copyright © 2024 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2024, ownCloud GmbH.
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

class AccountControllerSearchViewController: ClientItemViewController {
	convenience init(context inContext: ClientContext) {
		self.init(
			context: inContext,
			query: nil,
			itemsDatasource: OCDataSourceArray(),
			location: nil,
			highlightItemReference: nil,
			showRevealButtonForItems: false,
			emptyItemListIcon: UIImage(named: "search-empty", in: Bundle.sharedAppBundle, with: nil)!,
			emptyItemListTitleLocalized: HCL10n.Search.Empty.title,
			emptyItemListMessageLocalized: ""
		)
		// Use overlay empty state for search tab (suggestions and empty input)
		useOverlayEmptyState = true
		revoke(in: inContext, when: [ .connectionClosed ])
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		// Bring up search
		startSearch()
	}

	override var searchViewController: SearchViewController? {
		didSet {
			// Modify newly created SearchViewController before it is used
			searchViewController?.showCancelButton = false
			searchViewController?.hideNavigationButtons = false
		}
	}

	override func search(for viewController: SearchViewController, content: SearchViewController.Content?) {
		// Disable dragging of items, so keyboard control does not include "Drag Item"
		// in the accessibility actions invoked with Tab + Z for (Quick Access) suggestions
		dragInteractionEnabled = (content?.type == .suggestion) ? false : true

		super.search(for: viewController, content: content)
	}
}
