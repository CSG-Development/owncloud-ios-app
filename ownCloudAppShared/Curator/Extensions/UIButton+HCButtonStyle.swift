import UIKit

public extension UIButton {
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
					return darkMode ? HCColor.Grey.darken4 : HCColor.Grey.lighten3
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
					return darkMode ? HCColor.Grey.darken4 : HCColor.Grey.lighten3
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

extension UIButton {
		static func makeImageHighlightCapsuleButton(
			image: UIImage?,
			title: String,
			tintColor: UIColor = .systemBlue,
			imageHighlightColor: UIColor = .systemBlue.withAlphaComponent(0.2),
			imagePadding: CGFloat = 6,
			contentPadding: CGFloat = 8
		) -> UIButton {
			var config = UIButton.Configuration.plain()
			config.image = image
			config.title = title
			config.imagePlacement = .top
			config.imagePadding = imagePadding
			config.baseForegroundColor = tintColor

			config.contentInsets = NSDirectionalEdgeInsets(
				top: contentPadding,
				leading: contentPadding,
				bottom: contentPadding,
				trailing: contentPadding
			)

			let button = UIButton(configuration: config, primaryAction: nil)

			button.configurationUpdateHandler = { btn in
				btn.layoutIfNeeded()
				guard let iv = btn.imageView else { return }
				iv.layer.cornerRadius = iv.bounds.height / 2
				iv.layer.masksToBounds = true
				iv.backgroundColor = (btn.isHighlighted || btn.isSelected)
				? .green
					: .clear
				btn.configuration?.background.backgroundColor = .clear
			}

			button.addAction(UIAction { action in
				guard let btn = action.sender as? UIButton else { return }
				btn.isSelected.toggle()
			}, for: .touchUpInside)

			return button
		}

}

class ImageHighlightCapsuleButton: ThemeButton {
	private let highlightView = ThemeCSSView(withSelectors: [.help])
	private let highlightSize = CGSize(width: 68, height: 32)

	/// Designated initializer
	init(
		image: UIImage?,
		title: String
	) {
		super.init(frame: .zero)

		var config = UIButton.Configuration.plain()
		config.image = image
		config.title = title
		config.imagePlacement = .top
		config.imagePadding = 12
		config.baseForegroundColor = tintColor
		config.contentInsets = NSDirectionalEdgeInsets(
			top: 12,
			leading: 8,
			bottom: 4,
			trailing: 8
		)
		self.configuration = config

		highlightView.layer.cornerRadius = highlightSize.height / 2
		highlightView.layer.masksToBounds = true
		highlightView.isHidden = true
		highlightView.isUserInteractionEnabled = false
		insertSubview(highlightView, at: 0)

		configurationUpdateHandler = { [weak self] btn in
			btn.configuration?.background.backgroundColor = .clear
			self?.updateHighlightVisibility()
		}		
	}

	@available(*, unavailable) required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		// Center the highlightView on the imageView
		guard let iv = imageView else { return }
		highlightView.bounds = CGRect(origin: .zero, size: highlightSize)
		highlightView.center = iv.center
	}

	private func updateHighlightVisibility() {
		let css = activeThemeCSS
		let highlightBackgroundColor = css.getColor(.fill, selectors: [.help], for: self)
		let highlightForegroundColor = css.getColor(.stroke, selectors: [.help], for: self)
		let foregroundColor = css.getColor(.stroke, selectors: [], for: self)

		highlightView.backgroundColor = highlightBackgroundColor
		highlightView.isHidden = !(isHighlighted || isSelected)

		self.configuration?.imageColorTransformer = UIConfigurationColorTransformer { [weak self] _ in
			guard let self else { return .clear }
			return (self.isSelected ? highlightForegroundColor : foregroundColor) ?? .clear
		}
	}

	override var isHighlighted: Bool {
		didSet { updateHighlightVisibility() }
	}
	override var isSelected: Bool {
		didSet { updateHighlightVisibility() }
	}
}
