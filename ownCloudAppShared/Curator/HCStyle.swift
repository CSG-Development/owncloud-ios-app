import UIKit

/// Maps unique `HCColor` tokens onto component states.
public enum HCStyle {
	public enum Button {
		public enum State: CaseIterable {
			case normal
			case hover
			case pressed
			case disabled

			public init(_ controlState: UIControl.State, isHovered: Bool = false) {
				if controlState.contains(.disabled) {
					self = .disabled
				} else if controlState.contains(.highlighted) {
					self = .pressed
				} else if isHovered {
					self = .hover
				} else {
					self = .normal
				}
			}
		}

		public struct Colors {
			public let background: UIColor
			public let text: UIColor
			public let border: UIColor
			public let spinner: UIColor

			public var hasBorder: Bool {
				border.cgColor.alpha > 0.001
			}
		}

		public static func colors(
			for style: HCButtonStyle,
			state: State,
			isDark: Bool
		) -> Colors {
			switch style {
				case .primary(configuration: .filled):
					return primaryFilled(state: state, isDark: isDark)
				case .primary(configuration: .outlined):
					return primaryOutlined(state: state, isDark: isDark)
				case .primary(configuration: .plain):
					return primaryPlain(state: state, isDark: isDark)
				case .secondary(configuration: .filled):
					return secondaryFilled(state: state, isDark: isDark)
				case .secondary(configuration: .outlined):
					return secondaryOutlined(state: state, isDark: isDark)
				case .secondary(configuration: .plain):
					return secondaryPlain(state: state, isDark: isDark)
			}
		}

		public static func colors(
			for style: HCButtonStyle,
			controlState: UIControl.State,
			isDark: Bool,
			isHovered: Bool = false
		) -> Colors {
			colors(for: style, state: State(controlState, isHovered: isHovered), isDark: isDark)
		}
	}
}

private extension HCStyle.Button {
	static func primaryFilled(state: State, isDark: Bool) -> Colors {
		let spinner = isDark ? HCColor.Neutral.gray700 : HCColor.Neutral.gray200
		switch state {
			case .normal:
				return Colors(
					background: HCColor.Green.green400,
					text: HCColor.Neutral.black,
					border: HCColor.Neutral.gray600,
					spinner: spinner
				)
			case .hover:
				return Colors(
					background: HCColor.Green.green300,
					text: HCColor.Neutral.black,
					border: isDark ? HCColor.Neutral.gray400 : HCColor.Neutral.gray600,
					spinner: spinner
				)
			case .pressed:
				return Colors(
					background: HCColor.Green.green200,
					text: HCColor.Neutral.black,
					border: isDark ? HCColor.Neutral.gray300 : HCColor.Neutral.gray600,
					spinner: spinner
				)
			case .disabled:
				return filledDisabled(isDark: isDark)
		}
	}

	static func primaryOutlined(state: State, isDark: Bool) -> Colors {
		let link = HCColor.Green.link(isDark)
		switch state {
			case .normal:
				return Colors(background: HCColor.clear, text: link, border: link, spinner: link)
			case .hover:
				return Colors(
					background: HCColor.Green.green300.withAlphaComponent(0.20),
					text: link,
					border: link,
					spinner: link
				)
			case .pressed:
				return Colors(
					background: HCColor.Green.green500.withAlphaComponent(0.20),
					text: link,
					border: link,
					spinner: link
				)
			case .disabled:
				return outlinedDisabled(isDark: isDark)
		}
	}

	static func primaryPlain(state: State, isDark: Bool) -> Colors {
		let link = HCColor.Green.link(isDark)
		switch state {
			case .normal:
				return Colors(background: HCColor.clear, text: link, border: HCColor.clear, spinner: link)
			case .hover:
				return Colors(
					background: HCColor.Green.green300.withAlphaComponent(0.20),
					text: isDark ? HCColor.Green.green300 : HCColor.Green.green500,
					border: HCColor.clear,
					spinner: link
				)
			case .pressed:
				return Colors(
					background: HCColor.Green.green500.withAlphaComponent(0.20),
					text: link,
					border: HCColor.clear,
					spinner: link
				)
			case .disabled:
				return plainDisabled(isDark: isDark)
		}
	}

	static func secondaryFilled(state: State, isDark: Bool) -> Colors {
		let text = isDark ? HCColor.Neutral.gray850 : HCColor.Neutral.gray100
		let spinner = HCColor.Green.green400
		let border = HCColor.Neutral.gray600
		switch state {
			case .normal:
				return Colors(
					background: isDark ? HCColor.Neutral.gray100 : HCColor.Neutral.gray900,
					text: text,
					border: border,
					spinner: spinner
				)
			case .hover:
				return Colors(
					background: isDark ? HCColor.Neutral.gray300 : HCColor.Neutral.gray800,
					text: text,
					border: border,
					spinner: spinner
				)
			case .pressed:
				return Colors(
					background: isDark ? HCColor.Neutral.gray400 : HCColor.Neutral.gray700,
					text: text,
					border: border,
					spinner: spinner
				)
			case .disabled:
				return filledDisabled(isDark: isDark)
		}
	}

	static func secondaryOutlined(state: State, isDark: Bool) -> Colors {
		let spinner = HCColor.Green.link(isDark)
		switch state {
			case .normal:
				let onSurface = isDark ? HCColor.Neutral.gray100 : HCColor.Neutral.gray900
				return Colors(background: HCColor.clear, text: onSurface, border: onSurface, spinner: spinner)
			case .hover, .pressed:
				let emphasis = isDark ? HCColor.Neutral.gray400 : HCColor.Neutral.gray700
				return Colors(
					background: secondaryTransparentFill(state: state, isDark: isDark),
					text: emphasis,
					border: emphasis,
					spinner: spinner
				)
			case .disabled:
				return outlinedDisabled(isDark: isDark)
		}
	}

	static func secondaryPlain(state: State, isDark: Bool) -> Colors {
		let spinner = HCColor.Green.link(isDark)
		switch state {
			case .normal:
				let onSurface = isDark ? HCColor.Neutral.gray100 : HCColor.Neutral.gray900
				return Colors(background: HCColor.clear, text: onSurface, border: HCColor.clear, spinner: spinner)
			case .hover, .pressed:
				let emphasis = isDark ? HCColor.Neutral.gray400 : HCColor.Neutral.gray700
				return Colors(
					background: secondaryTransparentFill(state: state, isDark: isDark),
					text: emphasis,
					border: HCColor.clear,
					spinner: spinner
				)
			case .disabled:
				return plainDisabled(isDark: isDark)
		}
	}

	static func filledDisabled(isDark: Bool) -> Colors {
		Colors(
			background: HCColor.Neutral.disabledFill(isDark),
			text: HCColor.Neutral.gray900,
			border: HCColor.clear,
			spinner: HCColor.clear
		)
	}

	static func outlinedDisabled(isDark: Bool) -> Colors {
		let disabled = HCColor.Neutral.disabledFill(isDark)
		return Colors(background: HCColor.clear, text: disabled, border: disabled, spinner: HCColor.clear)
	}

	static func plainDisabled(isDark: Bool) -> Colors {
		Colors(
			background: HCColor.clear,
			text: HCColor.Neutral.disabledFill(isDark),
			border: HCColor.clear,
			spinner: HCColor.clear
		)
	}

	static func secondaryTransparentFill(state: State, isDark: Bool) -> UIColor {
		let base = isDark ? HCColor.Neutral.gray150 : HCColor.Neutral.grayDarken3
		switch state {
			case .hover:
				return base.withAlphaComponent(0.20)
			case .pressed:
				return base.withAlphaComponent(0.12)
			default:
				return HCColor.clear
		}
	}
}
