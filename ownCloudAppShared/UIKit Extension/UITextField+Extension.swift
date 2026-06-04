//
//  UITextField+Extension.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 09.08.22.
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

public enum SearchFilterChipStyle {
	public static let filterBarButtonHeight: CGFloat = 32
	public static let horizontalPadding: CGFloat = 8
	public static let iconLabelSpacing: CGFloat = 4
	public static let verticalPadding: CGFloat = 4
	private static let filterBarButtonHeightConstraintIdentifier = "filterBarButtonHeight"

	public static func filterBarButtonConfiguration(isDark: Bool, isSelected: Bool) -> UIButton.Configuration {
		var configuration = UIButton.Configuration.plain()
		let primaryColor = HCColor.Interaction.primarySolidNormal(isDark)
		configuration.baseForegroundColor = primaryColor
		configuration.contentInsets = NSDirectionalEdgeInsets(
			top: verticalPadding,
			leading: horizontalPadding,
			bottom: verticalPadding,
			trailing: horizontalPadding
		)
		configuration.imagePadding = iconLabelSpacing

		if isSelected {
			let selectedBackground = HCColor.Interaction.primaryTransparentNormal12(isDark)
			configuration.baseBackgroundColor = selectedBackground
			configuration.background.backgroundColor = selectedBackground
			configuration.background.cornerRadius = 1000
			configuration.cornerStyle = .capsule
		} else {
			configuration.baseBackgroundColor = .clear
			configuration.background.backgroundColor = .clear
		}

		return configuration
	}

	public static func applyFilterBarButtonHeight(to button: UIButton) {
		button.constraints
			.filter { $0.identifier == filterBarButtonHeightConstraintIdentifier }
			.forEach { button.removeConstraint($0) }

		let heightConstraint = button.heightAnchor.constraint(equalToConstant: filterBarButtonHeight)
		heightConstraint.identifier = filterBarButtonHeightConstraintIdentifier
		heightConstraint.isActive = true
	}

	public static var segmentTokenInsets: NSDirectionalEdgeInsets {
		NSDirectionalEdgeInsets(
			top: verticalPadding,
			leading: horizontalPadding,
			bottom: verticalPadding,
			trailing: horizontalPadding
		)
	}

	public static func segmentTokenColors(isDark: Bool) -> (background: UIColor, foreground: UIColor) {
		(HCColor.Content.border(isDark), HCColor.Constant.white(isDark))
	}
}

public extension UISearchTextField {
	func applyFilterChipAppearance(isDark: Bool) {
		let colors = SearchFilterChipStyle.segmentTokenColors(isDark: isDark)
		applyFilterChipAppearance(backgroundColor: colors.background, foregroundColor: colors.foreground, isDark: isDark)
	}

	func applyFilterChipAppearance(backgroundColor: UIColor, foregroundColor: UIColor, isDark: Bool) {
		layoutIfNeeded()

		var tokenContainerIndex = 0
		enumerateFilterTokenContainerViews { tokenView in
			//tokenView.backgroundColor = backgroundColor
			//tokenView.clipsToBounds = true
			//tokenView.layer.cornerRadius = tokenView.bounds.height / 2

			let isTagToken = tokenContainerIndex < tokens.count
				&& (tokens[tokenContainerIndex].representedObject as? SearchToken)?.isTagFilterToken == true
			tokenContainerIndex += 1

			let tagIconColor = HCColor.Constant.white(isDark)

			for subview in tokenView.subviewsRecursive {
				if let label = subview as? UILabel {
					label.textColor = foregroundColor
				}
				if let imageView = subview as? UIImageView {
					if isTagToken {
						imageView.image = HCIcon.tagIcon?.withRenderingMode(.alwaysTemplate)
						imageView.tintColor = tagIconColor
					} else {
						imageView.image = imageView.image?.withRenderingMode(.alwaysTemplate)
						imageView.tintColor = foregroundColor
					}
				}
			}
		}
	}

	private func enumerateFilterTokenContainerViews(_ visit: (UIView) -> Void) {
		enumerateSubviews { subview in
			guard subview !== self else { return }

			let labels = subview.subviews.compactMap { $0 as? UILabel }
			let hasIcon = subview.subviews.contains { $0 is UIImageView }
			let hasTitle = !labels.isEmpty
			let height = subview.bounds.height

			guard hasIcon, hasTitle, height >= 18, height <= 44, subview.bounds.width > 32 else {
				return
			}

			visit(subview)
		}
	}

	private func enumerateSubviews(_ visit: (UIView) -> Void) {
		func walk(_ view: UIView) {
			visit(view)
			for subview in view.subviews {
				walk(subview)
			}
		}

		walk(self)
	}
}

public extension UITextField {
	var cursorPosition : Int? {
		if let selectedTextRange = selectedTextRange, selectedTextRange.isEmpty {
			return offset(from: beginningOfDocument, to: selectedTextRange.start)
		}
		return nil
	}
}

public extension UISearchTextField {
	var cursorPositionInTextualRange : Int? {
		if let selectedTextRange = selectedTextRange, selectedTextRange.isEmpty {
			return offset(from: textualRange.start, to: selectedTextRange.start)
		}
		return nil
	}

	func textRange(from range: NSRange) -> UITextRange? {
		let textualRange = textualRange
		if let startPosition = position(from: textualRange.start, offset: range.location),
		   let endPosition = position(from: startPosition, in: .right, offset: range.length) {
		   	return textRange(from: startPosition, to: endPosition)
		}

		return nil
	}
}
