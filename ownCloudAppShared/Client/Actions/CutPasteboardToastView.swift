import UIKit
import SnapKit
import ownCloudSDK

/// Bottom snackbar shown after cutting items to the pasteboard.
public final class CutPasteboardToastView: UIView {
	public var onDismiss: (() -> Void)?

	private let cornerRadius: CGFloat = 4
	private let contentView = UIView()
	private let softShadowLayer = CALayer()
	private let hardShadowLayer = CALayer()

	private let stackView: UIStackView = {
		let stack = UIStackView()
		stack.axis = .horizontal
		stack.alignment = .center
		stack.spacing = 12
		stack.isLayoutMarginsRelativeArrangement = true
		stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12)
		return stack
	}()

	private let messageLabel: UILabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: 14, weight: .regular)
		label.numberOfLines = 0
		label.lineBreakMode = .byWordWrapping
		label.setContentHuggingPriority(.defaultLow, for: .horizontal)
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		return label
	}()

	private let closeButton: UIButton = {
		let button = UIButton(type: .system)
		button.setImage(HCIcon.cross, for: .normal)
		button.accessibilityLabel = OCLocalizedString("Common.cancel", nil)
		return button
	}()

	public init(message: String) {
		super.init(frame: .zero)
		messageLabel.text = message

		backgroundColor = .clear
		clipsToBounds = false
		layer.masksToBounds = false

		contentView.layer.cornerRadius = cornerRadius
		contentView.layer.cornerCurve = .continuous
		contentView.clipsToBounds = true

		configureShadowLayers()
		applyTheme()

		stackView.addArrangedSubview(messageLabel)
		stackView.addArrangedSubview(closeButton)

		addSubview(contentView)
		contentView.addSubview(stackView)

		contentView.snp.makeConstraints { make in
			make.edges.equalToSuperview()
		}
		stackView.snp.makeConstraints { make in
			make.edges.equalToSuperview()
		}
		closeButton.snp.makeConstraints { make in
			make.width.height.equalTo(28)
		}

		closeButton.addTarget(self, action: #selector(handleDismissTap), for: .touchUpInside)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	public override func layoutSubviews() {
		super.layoutSubviews()
		updateShadowLayers()
		layer.insertSublayer(softShadowLayer, at: 0)
		layer.insertSublayer(hardShadowLayer, at: 0)
	}

	public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
			applyTheme()
		}
	}

	private func configureShadowLayers() {
		softShadowLayer.shadowColor = UIColor.black.withAlphaComponent(0x1F / 255.0).cgColor
		softShadowLayer.shadowOffset = CGSize(width: 0, height: 1)
		softShadowLayer.shadowRadius = 18
		softShadowLayer.shadowOpacity = 1
		softShadowLayer.contentsScale = UIScreen.main.scale

		hardShadowLayer.shadowColor = UIColor.black.withAlphaComponent(0x24 / 255.0).cgColor
		hardShadowLayer.shadowOffset = CGSize(width: 0, height: 6)
		hardShadowLayer.shadowRadius = 10
		hardShadowLayer.shadowOpacity = 1
		hardShadowLayer.contentsScale = UIScreen.main.scale

		layer.insertSublayer(softShadowLayer, at: 0)
		layer.insertSublayer(hardShadowLayer, at: 0)
	}

	private func updateShadowLayers() {
		let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
		for shadowLayer in [softShadowLayer, hardShadowLayer] {
			shadowLayer.frame = bounds
			shadowLayer.cornerRadius = cornerRadius
			shadowLayer.shadowPath = path
			shadowLayer.backgroundColor = nil
			shadowLayer.masksToBounds = false
		}
	}

	private func applyTheme() {
		let isDark = traitCollection.userInterfaceStyle == .dark
		contentView.backgroundColor = HCColor.Structure.snackbarBackground(isDark)
		messageLabel.textColor = HCColor.Content.textPrimaryInverted(isDark)
		closeButton.tintColor = HCColor.Content.textPrimaryInverted(isDark)
		contentView.layer.borderWidth = 0
	}

	@objc private func handleDismissTap() {
		onDismiss?()
	}
}
