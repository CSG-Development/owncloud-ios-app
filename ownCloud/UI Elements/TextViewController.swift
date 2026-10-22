//
//  TextViewController.swift
//  ownCloud
//
//  Created by Felix Schwarz on 23.08.18.
//  Copyright © 2018 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2018, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import ownCloudAppShared

class TextViewController: UIViewController, Themeable {
	var textView : UITextView?

	var attributedText : NSAttributedString? {
		didSet {
			textView?.attributedText = attributedText
		}
	}
	var plainText : String? {
		didSet {
			textView?.text = plainText
		}
	}

	deinit {
		Theme.shared.unregister(client: self)
	}

	override func loadView() {
		textView = UITextView()

		textView?.isEditable = false
		textView?.allowsEditingTextAttributes = false

		self.view = textView

		if attributedText != nil {
			textView?.attributedText = attributedText
		} else {
			textView?.text = plainText
		}

		Theme.shared.register(client: self, applyImmediately: true)
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		textView?.apply(css: collection.css, properties: [.stroke, .fill])

		// License text is an attributed string with a font and no foreground color.
		// UITextView draws that black, and textColor does not replace it when appearance changes.
		let textColor = HCColor.Content.textPrimary(collection.isDark)

		textView?.textColor = textColor

		guard let textView, let attributedText, attributedText.length > 0 else { return }

		let coloredText = NSMutableAttributedString(attributedString: attributedText)
		coloredText.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: coloredText.length))

		guard !coloredText.isEqual(to: attributedText) else { return }

		let offset = textView.contentOffset
		self.attributedText = coloredText
		textView.textColor = textColor
		textView.contentOffset = offset
	}
}
