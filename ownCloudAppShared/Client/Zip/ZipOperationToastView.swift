import UIKit
import SnapKit
import ownCloudSDK

public final class ZipOperationToastView: UIView {
	public enum Style {
		case success
		case error
	}

	public var onDismiss: (() -> Void)?
	public var onRetry: (() -> Void)?
	public var onView: (() -> Void)?

	private let style: Style
	private let cornerRadius: CGFloat = 4

	/// Hosts the filled bar so shadow layers can sit behind it.
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

	private let retryButton: UIButton = {
		let button = UIButton(type: .system)
		button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
		button.setContentHuggingPriority(.required, for: .horizontal)
		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		return button
	}()

	private let viewButton: UIButton = {
		let button = UIButton(type: .system)
		button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
		button.setContentHuggingPriority(.required, for: .horizontal)
		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		return button
	}()

	public init(message: String, style: Style) {
		self.style = style
		super.init(frame: .zero)
		messageLabel.text = message
		retryButton.setTitle(HCL10n.Network.retry, for: .normal)
		viewButton.setTitle(HCL10n.ZipAction.Success.viewButton, for: .normal)

		backgroundColor = .clear
		clipsToBounds = false
		layer.masksToBounds = false

		contentView.layer.cornerRadius = cornerRadius
		contentView.layer.cornerCurve = .continuous
		contentView.clipsToBounds = true

		configureShadowLayers()
		applyTheme()

		stackView.addArrangedSubview(messageLabel)

		switch style {
		case .success:
			stackView.addArrangedSubview(viewButton)
		case .error:
			stackView.addArrangedSubview(retryButton)
			stackView.addArrangedSubview(closeButton)
		}

		addSubview(contentView)
		contentView.addSubview(stackView)

		contentView.snp.makeConstraints { make in
			make.edges.equalToSuperview()
		}
		stackView.snp.makeConstraints { make in
			make.edges.equalToSuperview()
			if style == .error {
				make.height.greaterThanOrEqualTo(68)
			}
		}

		closeButton.snp.makeConstraints { make in
			make.width.height.equalTo(28)
		}

		closeButton.addTarget(self, action: #selector(handleDismissTap), for: .touchUpInside)
		retryButton.addTarget(self, action: #selector(handleRetryTap), for: .touchUpInside)
		viewButton.addTarget(self, action: #selector(handleViewTap), for: .touchUpInside)

		configureErrorActions(showsRetry: false)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	public override func layoutSubviews() {
		super.layoutSubviews()
		updateShadowLayers()
		// Keep shadow layers behind the content fill.
		layer.insertSublayer(softShadowLayer, at: 0)
		layer.insertSublayer(hardShadowLayer, at: 0)
	}

	public func setMessage(_ message: String) {
		messageLabel.text = message
	}

	public func configureErrorActions(showsRetry: Bool) {
		guard style == .error else { return }
		retryButton.isHidden = !showsRetry
		closeButton.isHidden = false
	}

	public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
			applyTheme()
		}
	}

	private func configureShadowLayers() {
		// #0000001F, y: 1, blur: 18
		softShadowLayer.shadowColor = UIColor.black.withAlphaComponent(0x1F / 255.0).cgColor
		softShadowLayer.shadowOffset = CGSize(width: 0, height: 1)
		softShadowLayer.shadowRadius = 18
		softShadowLayer.shadowOpacity = 1
		softShadowLayer.contentsScale = UIScreen.main.scale

		// #00000024, y: 6, blur: 10
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
		switch style {
		case .success:
			contentView.backgroundColor = HCColor.Structure.snackbarBackground(isDark)
			messageLabel.textColor = HCColor.Content.textPrimaryInverted(isDark)
			viewButton.tintColor = HCColor.Interaction.primarySolidNormalInverted(isDark)
			contentView.layer.borderWidth = 0
		case .error:
			contentView.backgroundColor = HCColor.Symbolic.errorBackgroundOpaque(isDark)
			messageLabel.textColor = HCColor.Content.textPrimary(isDark)
			closeButton.tintColor = HCColor.Content.textSecondary(isDark)
			retryButton.tintColor = HCColor.Interaction.primarySolidNormal(isDark)
			contentView.layer.borderColor = HCColor.Symbolic.error(isDark).cgColor
			let scale = traitCollection.displayScale
			contentView.layer.borderWidth = scale > 0 ? 1.0 / scale : 1
		}
	}

	@objc private func handleDismissTap() {
		onDismiss?()
	}

	@objc private func handleRetryTap() {
		onRetry?()
	}

	@objc private func handleViewTap() {
		onView?()
	}
}
