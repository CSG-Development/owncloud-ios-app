//
//  ItemSearchScope.swift
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

// Common base class for query-modifying and custom query search scopes, implementing commonly used tools

open class ItemSearchScope : SearchScope {
	private var sortDescriptorObserver: NSKeyValueObservation?

	public override init(with context: ClientContext, cellStyle: CollectionViewCellStyle?, localizedName name: String, localizedPlaceholder placeholder: String? = nil, icon: UIImage? = nil) {
		super.init(with: context, cellStyle: cellStyle, localizedName: name, localizedPlaceholder: placeholder, icon: icon)

		tokenizer = CustomQuerySearchTokenizer(scope: self, clientContext: context)
		scopeViewController = createScopeViewController()

		sortDescriptorObserver = context.observe(\.sortDescriptor, changeHandler: { [weak self] context, change in
			self?.sortDescriptorChanged(to: context.sortDescriptor)
		})
	}

	deinit {
		sortDescriptorObserver?.invalidate()
	}

	open func sortDescriptorChanged(to sortDescriptor: SortDescriptor?) {
	}

	open var queryCondition: OCQueryCondition?
	open var selectedTagIDs: Set<String> = []
	open var selectedTagNames: Set<String> = []

	open override var isSelected: Bool {
		didSet {
			if !isSelected {
				// Dump queryCondition and results
				queryCondition = nil
				results = nil
			}
		}
	}

	open override func updateFor(_ searchElements: [SearchElement]) {
		if isSelected {
			var queryConditions : [OCQueryCondition] = []
			var tagIDs: Set<String> = []
			var tagNames: Set<String> = []

			for searchElement in searchElements {
				if let queryCondition = searchElement.representedObject as? OCQueryCondition {
					// Local scopes match tags via snapshots; server scope keeps tag: conditions in KQL.
					if queryCondition.isTagSearchCondition, !(self is ServerSideSearchScope) {
						if let tagName = queryCondition.value as? String, !tagName.isEmpty {
							tagNames.insert(tagName)
						}
					} else {
						queryConditions.append(queryCondition)
					}
				} else if let tagFilter = searchElement.representedObject as? SearchTagFilter {
					if let tagID = tagFilter.tagID, !tagID.hasPrefix("local:") {
						tagIDs.insert(tagID)
					}
					tagNames.insert(tagFilter.tagName)
				}
			}

			selectedTagIDs = tagIDs
			selectedTagNames = tagNames

			if queryConditions.count > 0 {
				queryCondition = OCQueryCondition.require(queryConditions)
			} else {
				queryCondition = nil
			}
		}
	}

	open var searchTerm: String? {
		return queryCondition?.composedSearchTerm
	}

	// MARK: - Subclassing points
	open func createScopeViewController() -> (UIViewController & SearchElementUpdating)? {
		return ItemSearchSuggestionsViewController(with: self)
	}

	// MARK: - Saved search support
	// - ItemSearchScope specific
	open var savedSearchScope: OCSavedSearchScope? { return nil }

	// - SearchScope subclassing
	open override var canSaveSearch: Bool {
		return (savedSearchScope != nil) && ((searchTerm?.count ?? 0) > 0)
	}
	open override var savedSearch: AnyObject? {
		if let savedSearchScope = savedSearchScope, let searchTerm = searchTerm {
			return OCSavedSearch(scope: savedSearchScope, location: nil, name: nil, isTemplate: false, searchTerm: searchTerm)
		}

		return nil
	}
	open override var canSaveTemplate: Bool {
		return canSaveSearch
	}
	open override var savedTemplate: AnyObject? {
		if let savedTemplate = savedSearch as? OCSavedSearch {
			savedTemplate.isTemplate = true
			return savedTemplate
		}
		return nil
	}
	open override func canRestore(savedTemplate: AnyObject) -> Bool {
		if let savedSearch = savedTemplate as? OCSavedSearch {
			return savedSearch.scope == savedSearchScope
		}
		return false
	}
	open override func restore(savedTemplate: AnyObject) -> [SearchElement]? {
		if let savedSearch = savedTemplate as? OCSavedSearch,
		   let elements = tokenizer?.parseSearchTerm(savedSearch.searchTerm, cursorOffset: nil, tokens: [], performUpdates: false) {
			return elements
		}

		return nil
	}
}
