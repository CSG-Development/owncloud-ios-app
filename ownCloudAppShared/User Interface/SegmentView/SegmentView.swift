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

	override open func setupSubviews() {
		super.setupSubviews()
		recreateAndLayoutItemViews()
	}

	func recreateAndLayoutItemViews() {
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

		if let lastSegmentView = (itemViews.last as? SegmentViewItemView) {
			// If the last view is a label, allow it to stretch and fill the space
			lastSegmentView.titleViewHugging = .defaultHigh
		}

		// Scroll View
		var hostView: UIView = self

		if isScrollable, scrollView == nil {
			scrollView = UIScrollView(frame: .zero)
			scrollView?.showsVerticalScrollIndicator = false
			scrollView?.showsHorizontalScrollIndicator = false
			scrollView?.translatesAutoresizingMaskIntoConstraints = false

			if let scrollView {
				hostView = scrollView

				embed(toFillWith: scrollView)
			}
		}

		// Embed
		hostView.embedHorizontally(views: itemViews, insets: insets, limitHeight: limitVerticalSpaceUsage, spacingProvider: { _, _ in
			return self.itemSpacing
		}, constraintsModifier: { constraintSet in
			switch self.truncationMode {
				case .none: break

				case .clipTail:
					constraintSet.lastTrailingOrBottomConstraint?.priority = .defaultHigh

				case .truncateHead:
					if !self.isScrollable {
						constraintSet.firstLeadingOrTopConstraint?.priority = .defaultHigh
					}

				case .truncateTail:
					if !self.isScrollable {
						constraintSet.lastTrailingOrBottomConstraint?.priority = .defaultHigh
					}
			}
			return constraintSet
		})

		// Layout without animation
		UIView.performWithoutAnimation {
			layoutIfNeeded()

			if isScrollable {
				scrollToTruncationTarget()
			}
		}
	}

	func scrollToTruncationTarget() {
		switch truncationMode {
			case .truncateTail:
				if let contentWidth = scrollView?.contentSize.width {
					scrollView?.scrollRectToVisible(CGRect(x: contentWidth-1, y: 0, width: 1, height: 1), animated: false)
				}

			case .truncateHead:
				scrollView?.scrollRectToVisible(CGRect(x: 0, y: 0, width: 1, height: 1), animated: false)

			default: break
		}
	}

	public override var bounds: CGRect {
		didSet {
			OnMainThread {
				self.scrollToTruncationTarget()
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
