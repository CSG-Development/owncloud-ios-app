import UIKit
import SnapKit
import ownCloudSDK

/// Bottom snackbar for network/device connectivity states.
public final class NetworkAvailabilityToastView: UIView {
	public enum Style {
		case card
		case snackbar
	}

	public var onDismiss: (() -> Void)?
	public var onRetry: (() -> Void)?

	private let style: Style

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
		label.font = .systemFont(ofSize: 14, weight: .medium)
		label.numberOfLines = 1
		label.adjustsFontSizeToFitWidth = true
		label.minimumScaleFactor = 0.8
		return label
	}()

	private let closeButton: UIButton = {
		let button = UIButton(type: .system)
		let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
		button.setImage(UIImage(systemName: "xmark", withConfiguration: configuration), for: .normal)
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

	public init(message: String, style: Style = .card) {
		self.style = style
		super.init(frame: .zero)
		messageLabel.text = message
		retryButton.setTitle(HCL10n.Network.retry, for: .normal)
		configureMessageLabel(for: style)

		switch style {
			case .card:
				layer.cornerRadius = 18
				layer.cornerCurve = .continuous
				layer.shadowColor = UIColor.black.cgColor
				layer.shadowOpacity = 0.18
				layer.shadowRadius = 8
				layer.shadowOffset = CGSize(width: 0, height: 2)
			case .snackbar:
				layer.cornerRadius = 4
				layer.cornerCurve = .continuous
				layer.shadowOpacity = 0
		}

		applyTheme()

		stackView.addArrangedSubview(messageLabel)
		stackView.addArrangedSubview(closeButton)
		stackView.addArrangedSubview(retryButton)

		addSubview(stackView)

		stackView.snp.makeConstraints { make in
			make.edges.equalToSuperview()
		}

		closeButton.snp.makeConstraints { make in
			make.width.height.equalTo(28)
		}

		closeButton.addTarget(self, action: #selector(handleDismissTap), for: .touchUpInside)
		retryButton.addTarget(self, action: #selector(handleRetryTap), for: .touchUpInside)

		isAccessibilityElement = false
		messageLabel.isAccessibilityElement = true
		messageLabel.accessibilityTraits = .staticText
		retryButton.isAccessibilityElement = true
		retryButton.accessibilityTraits = .button

		configure(for: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	public func setMessage(_ message: String) {
		messageLabel.text = message
	}

	public func configure(for kind: NetworkAvailabilityToastKind?) {
		switch kind {
			case .connectionLost:
				closeButton.isHidden = true
				retryButton.isHidden = false
			case .findingNetwork, .noInternet, .none:
				closeButton.isHidden = false
				retryButton.isHidden = true
		}
	}

	public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
			applyTheme()
		}
	}

	private func configureMessageLabel(for style: Style) {
		switch style {
			case .card:
				messageLabel.numberOfLines = 1
				messageLabel.lineBreakMode = .byTruncatingTail
				messageLabel.adjustsFontSizeToFitWidth = true
				messageLabel.minimumScaleFactor = 0.8
				stackView.alignment = .center
			case .snackbar:
				messageLabel.numberOfLines = 0
				messageLabel.lineBreakMode = .byWordWrapping
				messageLabel.adjustsFontSizeToFitWidth = false
				stackView.alignment = .center
				messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
				messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		}
	}

	private func applyTheme() {
		let isDark = traitCollection.userInterfaceStyle == .dark
		switch style {
			case .card:
				backgroundColor = HCColor.Structure.cardBackground(isDark)
				messageLabel.textColor = HCColor.Content.textPrimary(isDark)
				closeButton.tintColor = HCColor.Content.textSecondary(isDark)
				retryButton.tintColor = HCColor.Content.textSecondary(isDark)
				layer.borderColor = HCColor.Content.border(isDark).cgColor
				let scale = traitCollection.displayScale
				layer.borderWidth = scale > 0 ? 1.0 / scale : 0.5
			case .snackbar:
				backgroundColor = HCColor.Structure.snackbarBackground(isDark)
				messageLabel.textColor = HCColor.Content.textPrimaryInverted(isDark)
				closeButton.tintColor = HCColor.Content.textPrimaryInverted(isDark)
				retryButton.tintColor = HCColor.Content.textPrimaryInverted(isDark)
				layer.borderWidth = 0
		}
	}

	@objc private func handleDismissTap() {
		onDismiss?()
	}

	@objc private func handleRetryTap() {
		onRetry?()
	}
}
