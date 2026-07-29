//
//  FileListLayoutMetrics.swift
//  ownCloudAppShared
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2026, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 */

import UIKit

enum FileListLayoutMetrics {
	static let listItemHeight: CGFloat = 68
	static let sortBarHeight: CGFloat = 42
	static let statisticsFooterHeight: CGFloat = 54
	static let spaceHeaderHeight: CGFloat = 48
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

	static func gridTextAreaHeight(for layout: FileListItemCell.Layout) -> CGFloat {
		switch layout {
			case .grid:
				return gridTitleSpacing + gridTitleMaxHeight + gridDetailSpacing + gridDetailHeight + gridBottomInset
			case .gridLowDetail:
				return gridTitleSpacing + gridTitleMaxHeight + gridBottomInset
			case .gridNoDetail:
				return gridBottomInset + 11
			case .list:
				return 0
		}
	}

	static func gridTextAreaHeight(for itemLayout: ItemLayout) -> CGFloat {
		gridTextAreaHeight(for: cellLayout(for: itemLayout))
	}

	static func cellLayout(for itemLayout: ItemLayout) -> FileListItemCell.Layout {
		switch itemLayout {
			case .list: return .list
			case .grid: return .grid
			case .gridLowDetail: return .gridLowDetail
			case .gridNoDetail: return .gridNoDetail
		}
	}

	static func gridItemHeight(columnWidth: CGFloat, itemLayout: ItemLayout) -> CGFloat {
		gridItemHeight(columnWidth: columnWidth, layout: cellLayout(for: itemLayout))
	}

	static func gridItemHeight(columnWidth: CGFloat, layout: FileListItemCell.Layout) -> CGFloat {
		let iconWidth = max(0, columnWidth - (2 * gridIconHorizontalInset))
		let iconHeight = iconWidth * gridIconAspect
		return gridIconTopInset + iconHeight + gridTextAreaHeight(for: layout)
	}

	static func gridItemHeight(columnWidth: CGFloat) -> CGFloat {
		gridItemHeight(columnWidth: columnWidth, layout: .grid)
	}

	static func makeGridSection(itemLayout: ItemLayout, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
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
		let itemHeight = gridItemHeight(columnWidth: innerWidth, itemLayout: itemLayout) + cellInsets.top + cellInsets.bottom

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
