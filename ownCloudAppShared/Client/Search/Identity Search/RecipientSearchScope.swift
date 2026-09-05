//
//  RecipientSearchScope.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 19.04.23.
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

open class RecipientSearchScope: SearchScope {
	var recipientSearchController: OCRecipientSearchController?
	var item: OCItem

	public typealias RecipientFilter = (OCIdentity) -> Bool

	public init(with context: ClientContext, cellStyle: CollectionViewCellStyle?, item: OCItem, localizedName name: String, localizedPlaceholder placeholder: String? = nil, icon: UIImage? = nil, filter: RecipientFilter? = nil) {
		if let core = context.core {
			recipientSearchController = core.recipientSearchController(for: item)
			// Search from the first character so single-letter usernames and display names can be found.
			// Server capabilities typically report search_min_length=2, which skipped the request until a second character.
			recipientSearchController?.minimumSearchTermLength = 1
		}

		self.item = item

		super.init(with: context, cellStyle: cellStyle, localizedName: name, localizedPlaceholder: placeholder, icon: icon)

		tokenizer = SearchTokenizer(scope: self, clientContext: clientContext)

		if let recipientsDataSource = recipientSearchController?.recipientsDataSource {
			if let filter {
				let filteringDatasource = OCDataSourceComposition(sources: [])
				filteringDatasource.addSources([recipientsDataSource])
				filteringDatasource.setFilter({ source, itemRef in
					if let itemRecord = try? source.record(forItemRef: itemRef),
					   let identity = itemRecord.item as? OCIdentity {
						return filter(identity)
					}
					return true
				}, for: recipientsDataSource)
				results = filteringDatasource
			} else {
				results = recipientsDataSource
			}
		}
	}

	open override func updateFor(_ searchElements: [SearchElement]) {
		let searchTerm = searchElements.composedSearchTerm

		recipientSearchController?.searchTerm = searchTerm
	}
}
