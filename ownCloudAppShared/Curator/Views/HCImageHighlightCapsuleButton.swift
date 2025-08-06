import UIKit

public final class HCImageHighlightCapsuleButton: ThemeButton {
	private let highlightView = ThemeCSSView(withSelectors: [.help])
	private let highlightSize = CGSize(width: 68, height: 32)

	public init(image: UIImage?, selectedImage: UIImage?, title: String) {
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
			guard let self else { return }
			btn.configuration?.background.backgroundColor = .clear
			btn.configuration?.image = self.isSelected ? selectedImage : image
			self.updateHighlightVisibility()
		}
	}

	@available(*, unavailable) required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	public override func layoutSubviews() {
		super.layoutSubviews()
		// Center the highlightView on the imageView
		guard let iv = imageView else { return }
		highlightView.bounds = CGRect(origin: .zero, size: highlightSize)
		highlightView.center = iv.center
	}

	public override var isHighlighted: Bool {
		didSet { updateHighlightVisibility() }
	}

	public override var isSelected: Bool {
		didSet { updateHighlightVisibility() }
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
}
