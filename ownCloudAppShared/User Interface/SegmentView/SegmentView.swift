//
//  SegmentView.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 29.09.22.
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

extension ThemeCSSSelector {
	static let segments = ThemeCSSSelector(rawValue: "segments")
}

public class SegmentView: ThemeView, ThemeCSSAutoSelector, ThemeCSSChangeObserver {

	public let cssAutoSelectors: [ThemeCSSSelector] = [.segments]

	public enum TruncationMode {
		case none
		case clipTail
		case truncateHead
		case truncateTail
	}

 	open var items: [SegmentViewItem] {
		willSet {
			for item in items {
				item.segmentView = nil
			}
		}

 		didSet {
 			if superview != nil {
				recreateAndLayoutItemViews()
			}
		}
	}
 	open var itemSpacing: CGFloat = 5
 	open var truncationMode: TruncationMode = .none {
 		didSet {
 			if truncationMode != oldValue {
 				recreateAndLayoutItemViews()
			}
		}
	}
 	open var insets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
 	open var limitVerticalSpaceUsage: Bool = false

	private var isScrollable: Bool

	public init(with items: [SegmentViewItem], truncationMode: TruncationMode, scrollable: Bool = false, limitVerticalSpaceUsage: Bool = false) {
		isScrollable = scrollable
		self.limitVerticalSpaceUsage = limitVerticalSpaceUsage

		self.items = items

		super.init()

		self.truncationMode = truncationMode
		isOpaque = false
		backgroundColor = .clear
	}

	required public init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private var itemViews: [UIView] = []
	private var borderMaskView: UIView?
	private var scrollView: UIScrollView?
	private var hasAutoScrolledToTruncationTarget: Bool = false

	override open func setupSubviews() {
		super.setupSubviews()
		recreateAndLayoutItemViews()
	}

	func recreateAndLayoutItemViews() {
		hasAutoScrolledToTruncationTarget = false
		// Remove existing views
		for itemView in itemViews {
			itemView.removeFromSuperview()
		}

		itemViews.removeAll()

		// Create new views
		for item in items {
			item.segmentView = self

			if let view = item.view {
				itemViews.append(view)
			}
		}

		let lastTruncatableIndex = itemViews.lastIndex(where: { itemView in
			(itemView as? SegmentViewItemView)?.titleView != nil
		})

		for (index, itemView) in itemViews.enumerated() {
			(itemView as? SegmentViewItemView)?.applyLayoutPolicy(
				index: index,
				count: itemViews.count,
				truncationMode: truncationMode,
				isScrollable: isScrollable,
				isTruncationTarget: index == lastTruncatableIndex
			)
		}

		clipsToBounds = !isScrollable && truncationMode == .clipTail

		// Scroll View
		var hostView: UIView = self

		if isScrollable {
			if scrollView == nil {
				scrollView = UIScrollView(frame: .zero)
				scrollView?.showsVerticalScrollIndicator = false
				scrollView?.showsHorizontalScrollIndicator = false
				scrollView?.translatesAutoresizingMaskIntoConstraints = false
			}

			if let scrollView {
				hostView = scrollView
				if scrollView.superview == nil {
					embed(toFillWith: scrollView)
				}
			}
		}

		// Embed
		var enclosingAnchors: UIView.AnchorSet?
		if let scrollView, isScrollable {
			// Use contentLayoutGuide for horizontal content sizing and frameLayoutGuide for vertical alignment
			enclosingAnchors = UIView.AnchorSet(
				leadingAnchor: scrollView.contentLayoutGuide.leadingAnchor,
				trailingAnchor: scrollView.contentLayoutGuide.trailingAnchor,
				topAnchor: scrollView.frameLayoutGuide.topAnchor,
				bottomAnchor: scrollView.frameLayoutGuide.bottomAnchor,
				centerXAnchor: scrollView.frameLayoutGuide.centerXAnchor,
				centerYAnchor: scrollView.frameLayoutGuide.centerYAnchor
			)
		}

		let lastTrailingRelation: NSLayoutConstraint.Relation = isScrollable ? .equal : .lessThanOrEqual

		hostView.embedHorizontally(
			views: itemViews,
			insets: insets,
			enclosingAnchors: enclosingAnchors,
			limitHeight: limitVerticalSpaceUsage,
			lastTrailingRelation: lastTrailingRelation,
			spacingProvider: { _, _ in
				return self.itemSpacing
			},
			constraintsModifier: { constraintSet in
				guard !self.isScrollable else { return constraintSet }

				constraintSet.firstLeadingOrTopConstraint?.priority = .required

				switch self.truncationMode {
					case .none, .truncateTail:
						constraintSet.lastTrailingOrBottomConstraint?.priority = .required

					case .clipTail:
						constraintSet.lastTrailingOrBottomConstraint?.priority = .defaultLow

					case .truncateHead:
						break
				}

				return constraintSet
			}
		)

		// Layout without animation
		UIView.performWithoutAnimation {
			layoutIfNeeded()

			if isScrollable {
				// Ensure scroll after current layout pass, when contentSize is final
				DispatchQueue.main.async {
					self.scrollToTruncationTarget()
					self.hasAutoScrolledToTruncationTarget = true
				}
			}
		}
	}

	func scrollToTruncationTarget() {
		guard let scrollView, isScrollable else { return }
		switch truncationMode {
			case .truncateTail:
				let contentWidth = scrollView.contentSize.width
				let boundsWidth = scrollView.bounds.width
				let rightInset = scrollView.contentInset.right
				let leftInset = scrollView.contentInset.left
				let maxOffsetX = max(-leftInset, contentWidth - boundsWidth + rightInset)
				scrollView.setContentOffset(CGPoint(x: maxOffsetX, y: -scrollView.contentInset.top), animated: false)

			case .truncateHead:
				scrollView.setContentOffset(CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top), animated: false)

			default: break
		}
	}

	public override var bounds: CGRect {
		didSet {
			if isScrollable && !hasAutoScrolledToTruncationTarget {
				OnMainThread {
					self.scrollToTruncationTarget()
					self.hasAutoScrolledToTruncationTarget = true
				}
			}
		}
	}

	public func cssSelectorsChanged() {
		for item in items {
			item._view = nil
		}
		recreateAndLayoutItemViews()
	}
}
