//
//  TrashLayoutMetrics.swift
//  ownCloud
//
//  Copyright © 2025 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2025, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit

enum TrashFeatures {
	/// When `false`, folder taps are ignored and the list always shows the trash root.
	static let folderNavigationEnabled = false

	/// When `false`, file taps do nothing outside selection mode.
	static let filePreviewEnabled = false
}

enum TrashLayoutMetrics {
	static let retentionPeriodDays = 30
	static let listItemHeight: CGFloat = 68
	static let gridSpacing: CGFloat = 4
	static let gridMinimumWidth: CGFloat = 130
	static let gridMaximumWidth: CGFloat = 160
	static let gridIconAspect: CGFloat = 3.0 / 4.0
	static let gridIconHorizontalInset: CGFloat = 10
	static let gridIconTopInset: CGFloat = 5
	static let gridTitleSpacing: CGFloat = 5
	static let gridTitleMaxHeight: CGFloat = 36
	static let gridDetailSpacing: CGFloat = 2
	static let gridDetailHeight: CGFloat = 16
	static let gridBottomInset: CGFloat = 5

	static func gridItemHeight(columnWidth: CGFloat) -> CGFloat {
		let iconWidth = max(0, columnWidth - (2 * gridIconHorizontalInset))
		let iconHeight = iconWidth * gridIconAspect
		return gridIconTopInset
			+ iconHeight
			+ gridTitleSpacing
			+ gridTitleMaxHeight
			+ gridDetailSpacing
			+ gridDetailHeight
			+ gridBottomInset
	}

	static func makeGridSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
		let sectionInsets = NSDirectionalEdgeInsets(
			top: gridSpacing,
			leading: gridSpacing,
			bottom: gridSpacing,
			trailing: gridSpacing
		)
		let cellInsets = NSDirectionalEdgeInsets(
			top: gridSpacing / 2,
			leading: gridSpacing / 2,
			bottom: gridSpacing / 2,
			trailing: gridSpacing / 2
		)

		let availableWidth = layoutEnvironment.container.effectiveContentSize.width
			- sectionInsets.leading
			- sectionInsets.trailing
		var groupInsets = NSDirectionalEdgeInsets.zero

		var totalItemWidth = gridMinimumWidth + cellInsets.leading + cellInsets.trailing
		var maxItemCount = floor(availableWidth / totalItemWidth)
		if maxItemCount < 1 {
			maxItemCount = 1
		}

		if gridMaximumWidth > gridMinimumWidth {
			let maxTotalWidth = floor(availableWidth / maxItemCount)
			let maximumTotalWidth = gridMaximumWidth + cellInsets.leading + cellInsets.trailing
			totalItemWidth = min(maxTotalWidth, maximumTotalWidth)
		}

		let unusedWidth = availableWidth - (maxItemCount * totalItemWidth)
		let extraLeadingTrailingSpace = floor(unusedWidth / 2.0)
		groupInsets.leading += extraLeadingTrailingSpace
		groupInsets.trailing += extraLeadingTrailingSpace

		let innerWidth = totalItemWidth - cellInsets.leading - cellInsets.trailing
		let itemHeight = gridItemHeight(columnWidth: innerWidth) + cellInsets.top + cellInsets.bottom

		let itemSize = NSCollectionLayoutSize(
			widthDimension: .absolute(totalItemWidth),
			heightDimension: .absolute(itemHeight)
		)
		let item = NSCollectionLayoutItem(layoutSize: itemSize)
		item.contentInsets = cellInsets

		let group = NSCollectionLayoutGroup.horizontal(
			layoutSize: NSCollectionLayoutSize(
				widthDimension: .fractionalWidth(1.0),
				heightDimension: .absolute(itemHeight)
			),
			subitems: [item]
		)
		group.contentInsets = groupInsets

		let section = NSCollectionLayoutSection(group: group)
		section.contentInsets = sectionInsets
		section.interGroupSpacing = 0
		return section
	}
}
