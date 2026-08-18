import UIKit

enum FileListLayoutMetrics {
	static let listItemHeight: CGFloat = 68
	static let sortBarHeight: CGFloat = 42
	/// Space between the sort bar and the file list below it.
	static let sortBarBottomSpacing: CGFloat = 8
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

	struct CompositionalConfiguration {
		var itemLayout: ItemLayout
		var showsSpaceHeader: Bool
		var showsStatisticsFooter: Bool
		/// `nil` means the activity section is empty (near-zero height).
		var activitySectionHeight: CGFloat?
		var swipeActionsProvider: ((IndexPath) -> UISwipeActionsConfiguration?)?
	}

	static func makeCompositionalLayout(configuration: @escaping () -> CompositionalConfiguration) -> UICollectionViewLayout {
		UICollectionViewCompositionalLayout { sectionIndex, environment in
			let config = configuration()

			if sectionIndex == FileListSection.zipOperations.rawValue {
				guard let height = config.activitySectionHeight else {
					let empty = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(0.01))
					let item = NSCollectionLayoutItem(layoutSize: empty)
					let group = NSCollectionLayoutGroup.vertical(layoutSize: empty, subitems: [item])
					return NSCollectionLayoutSection(group: group)
				}
				let itemSize = NSCollectionLayoutSize(
					widthDimension: .fractionalWidth(1.0),
					heightDimension: .absolute(height)
				)
				let item = NSCollectionLayoutItem(layoutSize: itemSize)
				let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
				let section = NSCollectionLayoutSection(group: group)
				section.contentInsets = .zero
				return section
			}

			let section: NSCollectionLayoutSection
			if config.itemLayout == .list {
				var listConfig = UICollectionLayoutListConfiguration(appearance: .plain)
				listConfig.backgroundColor = .clear
				listConfig.showsSeparators = true
				if config.showsSpaceHeader {
					listConfig.headerMode = .supplementary
				}
				if config.showsStatisticsFooter {
					listConfig.footerMode = .supplementary
				}
				listConfig.trailingSwipeActionsConfigurationProvider = { indexPath in
					config.swipeActionsProvider?(indexPath)
				}
				section = NSCollectionLayoutSection.list(using: listConfig, layoutEnvironment: environment)
			} else {
				section = makeGridSection(itemLayout: config.itemLayout, layoutEnvironment: environment)
			}

			var boundaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []
			if config.showsSpaceHeader {
				boundaryItems.append(NSCollectionLayoutBoundarySupplementaryItem(
					layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(spaceHeaderHeight)),
					elementKind: FileListSupplementaryKind.spaceHeader,
					alignment: .top
				))
			}
			if config.showsStatisticsFooter {
				boundaryItems.append(NSCollectionLayoutBoundarySupplementaryItem(
					layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(statisticsFooterHeight)),
					elementKind: FileListSupplementaryKind.statisticsFooter,
					alignment: .bottom
				))
			}
			if !boundaryItems.isEmpty {
				section.boundarySupplementaryItems = boundaryItems
			}

			return section
		}
	}
}
