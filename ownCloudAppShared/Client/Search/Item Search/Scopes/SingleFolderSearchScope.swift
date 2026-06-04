//
//  SingleFolderSearchScope.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 25.08.22.
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

// Search scope that modifies an existing OCQuery so that it only returns matching results
// Used for folder-only search

open class QueryModifyingSearchScope : ItemSearchScope {
	public override var isSelected: Bool {
		didSet {
			if let query = clientContext.query {
				if isSelected {
					// Modify existing query provided via clientContext
					results = query.queryResultsDataSource
				}
			}
		}
	}

	open override var queryCondition: OCQueryCondition? {
		didSet {
			applyQueryFilters()
		}
	}

	open override func updateFor(_ searchElements: [SearchElement]) {
		super.updateFor(searchElements)
		if isSelected {
			applyQueryFilters()
		}
	}

	private var hasActiveTagFilter: Bool {
		!selectedTagIDs.isEmpty || !selectedTagNames.isEmpty
	}

	private func applyQueryFilters() {
		let queryCondition = queryCondition
		let hasNonTagUserQuery = queryCondition != nil
		let configuration = LocalSearchFilterConfiguration(
			nonTagCondition: queryCondition,
			selectedTagIDs: selectedTagIDs,
			selectedTagNames: selectedTagNames,
			maxResultCount: nil,
			allowUnknownTagPassThrough: false,
			bookmark: clientContext.accountConnection?.bookmark ?? clientContext.core?.bookmark,
			hasNonTagUserQuery: hasNonTagUserQuery
		)

		guard let query = clientContext.query else { return }

		if queryCondition != nil || hasActiveTagFilter {
			let filterHandler: OCQueryFilterHandler = { (_, _, item) -> Bool in
				guard let item else { return false }
				return !LocalSearchFilterAdapter.filter([item], configuration: configuration).isEmpty
			}

			if let filter = query.filter(withIdentifier: "text-search") {
				query.updateFilter(filter, applyChanges: { filterToChange in
					(filterToChange as? OCQueryFilter)?.filterHandler = filterHandler
				})
			} else {
				query.addFilter(OCQueryFilter(handler: filterHandler), withIdentifier: "text-search")
			}

			if let filter = query.filter(withIdentifier: "tag-search") {
				query.removeFilter(filter)
			}
		} else {
			if let filter = query.filter(withIdentifier: "text-search") {
				query.removeFilter(filter)
			}
			if let filter = query.filter(withIdentifier: "tag-search") {
				query.removeFilter(filter)
			}
		}

	}
}

// Subclass
open class SingleFolderSearchScope : QueryModifyingSearchScope {
	open override class var descriptor: SearchScopeDescriptor {
		return SearchScopeDescriptor(identifier: "folder", localizedName: OCLocalizedString("Folder", nil), localizedDescription: OCLocalizedString("Searches the current folder ONLY.", nil), icon: OCSymbol.icon(forSymbolName: "folder"), searchableContent: .itemName, scopeCreator: { (clientContext, cellStyle, descriptor) in
			if clientContext.query?.queryLocation != nil {
				return SingleFolderSearchScope(with: clientContext, cellStyle: nil, localizedName: descriptor.localizedName, localizedPlaceholder: OCLocalizedString("Search folder", nil), icon: descriptor.icon)
			}
			return nil
		})
	}

	open override var savedSearchScope: OCSavedSearchScope? {
		return .folder
	}
	open override var canSaveSearch: Bool {
		return true
	}
	open override var canSaveTemplate: Bool {
		return super.canSaveSearch
	}

	open override var savedSearch: AnyObject? {
		if let savedSearch = super.savedSearch as? OCSavedSearch {
			savedSearch.location = clientContext.query?.queryLocation
			return savedSearch
		}
		return nil
	}

	open override var savedTemplate: AnyObject? {
		if let savedTemplate = super.savedSearch as? OCSavedSearch {
			savedTemplate.location = clientContext.query?.queryLocation
			savedTemplate.isTemplate = true
			return savedTemplate
		}
		return nil
	}
}

public extension SearchScopeDescriptor {
	static var folder = SingleFolderSearchScope.descriptor
}
