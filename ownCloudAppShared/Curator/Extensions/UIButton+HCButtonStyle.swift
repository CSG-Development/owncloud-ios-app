import UIKit

public extension UIButton {
	func setTitle(title: String, style: HCButtonStyle, darkMode: Bool) {
		applyHCButtonStyle(title: title, style: style, isDark: darkMode)
	}

	func applyHCButtonStyle(
		title: String,
		style: HCButtonStyle,
		isDark: Bool,
		icon: UIImage? = nil,
		contentInsets: NSDirectionalEdgeInsets? = nil
	) {
		let updateConfiguration: (UIButton, inout UIButton.Configuration?) -> Void = { button, configuration in
			let colors = HCStyle.Button.colors(
				for: style,
				controlState: button.state,
				isDark: isDark,
				isHovered: button.isHovered
			)

			configuration = .filled()
			configuration?.cornerStyle = .capsule
			configuration?.titleAlignment = .center
			configuration?.background.backgroundColor = colors.background
			if let contentInsets {
				configuration?.contentInsets = contentInsets
			}

			if colors.hasBorder {
				configuration?.background.strokeWidth = 1.0
				configuration?.background.strokeOutset = 0.5
				configuration?.background.strokeColor = colors.border
			} else {
				configuration?.background.strokeWidth = 0
				configuration?.background.strokeColor = .clear
			}

			if let icon {
				configuration?.image = icon.withTintColor(colors.text, renderingMode: .alwaysOriginal)
				configuration?.imagePadding = 8
				configuration?.imagePlacement = .leading
			}

			var attributedTitle = AttributedString(title)
			attributedTitle.foregroundColor = colors.text
			attributedTitle.font = UIFont.systemFont(ofSize: 14, weight: .medium)
			configuration?.attributedTitle = attributedTitle
			configuration?.baseForegroundColor = colors.text
		}

		updateConfiguration(self, &configuration)
		configurationUpdateHandler = { button in
			updateConfiguration(button, &button.configuration)
		}
	}
}
