//
//  SearchElement.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 12.08.22.
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

extension OCQueryCondition {
	/// Tag tokens from the search bar (`tag:name`) — handled via local tag snapshots, not OCQuery properties.
	var isTagSearchCondition: Bool {
		let propertyName = property?.rawValue
		return propertyName == "tag" || propertyName == "tags"
	}
}

open class SearchElement: NSObject {
	open var text: String
	open var inputComplete: Bool

	open var representedObject: AnyObject?

	required public init(text: String, representedObject: AnyObject? = nil, inputComplete: Bool) {
		self.text = text
		self.inputComplete = inputComplete

		super.init()

		self.representedObject = representedObject
	}
}

open class SearchToken: SearchElement {
	open var icon: UIImage?

	var isTagFilterToken: Bool {
		if representedObject is SearchTagFilter {
			return true
		}
		if let condition = representedObject as? OCQueryCondition {
			return condition.isTagSearchCondition
		}
		return false
	}

	required public init(text: String, icon: UIImage?, representedObject: AnyObject?, inputComplete: Bool) {
		super.init(text: text, representedObject: representedObject, inputComplete: inputComplete)

		self.icon = icon
	}

	required public init(text: String, representedObject: AnyObject? = nil, inputComplete: Bool) {
		fatalError("init(text:representedObject:inputComplete:) has not been implemented")
	}
}

open class SearchTagFilter: NSObject {
	public let tagID: String?
	public let tagName: String

	public init(tagID: String?, tagName: String) {
		self.tagID = tagID
		self.tagName = tagName
		super.init()
	}
}

extension SearchToken {
	var uiSearchToken: UISearchToken {
		let tokenIcon: UIImage?
		if isTagFilterToken {
			tokenIcon = HCIcon.tagIcon?.withRenderingMode(.alwaysTemplate)
		} else {
			tokenIcon = icon
		}

		let token = UISearchToken(icon: tokenIcon, text: text)
		token.representedObject = self

		return token
	}
}

extension [SearchElement] {
	var composedSearchTerm: String {
		return compactMap({ element in return element.text }).joined(separator: " ")
	}
}
