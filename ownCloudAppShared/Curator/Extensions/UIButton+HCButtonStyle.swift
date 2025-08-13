import UIKit

extension UIButton {
	func setTitle(title: String, style: HCButtonStyle, darkMode: Bool) {
		let updateConfiguration: ((_ state: UIControl.State, _ configuration: inout UIButton.Configuration?) -> Void) = { state, configuration in
			let backgroundColor = self.backgroundColor(style: style, state: state, darkMode: darkMode)
			let foregroundColor = self.foregroundColor(style: style, state: state, darkMode: darkMode)
			let isOutlined = style.isOutlined

			configuration = .filled()

			if isOutlined {
				configuration?.background.strokeWidth = 1.0
				configuration?.background.strokeOutset = 0.5
				configuration?.background.strokeColor = foregroundColor
			}

			configuration?.cornerStyle = .capsule
			configuration?.background.backgroundColor = backgroundColor ?? .clear

			var attributedTitle = AttributedString(title)
			attributedTitle.foregroundColor = foregroundColor
			attributedTitle.font = UIFont.systemFont(ofSize: 14, weight: .medium)
			configuration?.attributedTitle = attributedTitle
		}
		updateConfiguration(.normal, &configuration)

		configurationUpdateHandler = { _ in
			updateConfiguration(self.state, &self.configuration)
		}
	}

	private func backgroundColor(
		style: HCButtonStyle,
		state: UIControl.State,
		darkMode: Bool
	) -> UIColor? {
		switch style {
		case let .primary(configuration: configuration):
			switch configuration {
			case .filled:
				switch state {
				case .highlighted:
					return darkMode ? HCColor.Blue.lighten3 : HCColor.Blue.darken1
				case .disabled:
					return HCColor.Content.disabledBackground(darkMode)
				default:
					return darkMode ? HCColor.Blue.lighten2 : HCColor.Blue.darken2
				}
			case .outlined, .plain:
				switch state {
				case .highlighted:
					return darkMode
						? HCColor.Transparencies.blueLighten3_12
						: HCColor.Transparencies.blueDarken1_12
				default:
					return nil
				}
			}
		case let .secondary(configuration: configuration):
			switch configuration {
			case .filled:
				switch state {
				case .highlighted:
					return darkMode ? HCColor.Grey.lighten3 : HCColor.Grey.darken3
				case .disabled:
					return HCColor.Content.disabledBackground(darkMode)
				default:
					return darkMode ? HCColor.white : HCColor.Grey.darken4
				}
			case .outlined, .plain:
				switch state {
				case .highlighted:
					return darkMode
						? HCColor.Transparencies.white_12 : HCColor.Transparencies.greyDarken3_12
				default:
					return nil
				}
			}
		}
	}

	private func foregroundColor(
		style: HCButtonStyle,
		state: UIControl.State,
		darkMode: Bool
	) -> UIColor? {
		switch style {
		case let .primary(configuration: configuration):
			switch configuration {
			case .filled:
				switch state {
				case .disabled:
					return HCColor.Grey.grey
				default:
					return darkMode ? HCColor.Text.lightModePrimary : HCColor.Text.darkModePrimary
				}
			case .outlined, .plain:
				switch state {
				case .highlighted:
					return darkMode ? HCColor.Blue.lighten3 : HCColor.Blue.darken1
				default:
					return darkMode ? HCColor.Blue.lighten2 : HCColor.Blue.darken2
				}
			}
		case let .secondary(configuration: configuration):
			switch configuration {
			case .filled:
				switch state {
				case .disabled:
					return HCColor.Grey.grey
				default:
					return darkMode ? HCColor.Text.lightModePrimary : HCColor.Text.darkModePrimary
				}
			case .outlined, .plain:
				switch state {
				case .highlighted:
					return darkMode ? HCColor.Grey.lighten3 : HCColor.Grey.darken3
				default:
					return darkMode ? HCColor.white : HCColor.Grey.darken4
				}
			}
		}
	}
}
