import UIKit
import SnapKit
import ownCloudSDK

/// Compact pill-shaped toast shown at the bottom of the content container when no
/// connectivity has been observed for the configured timeout. Provides a close (×)
/// button so the user can dismiss it manually.
public final class NetworkAvailabilityToastView: UIView {
	public enum Style {
		case card
		case snackbar
	}

	public var onDismiss: (() -> Void)?

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

	/// Updates the message shown in the toast. Safe to call while the toast is visible —
	/// callers should animate the layout change themselves if desired.
	public func setMessage(_ message: String) {
		messageLabel.text = message
	}

	public init(message: String, style: Style = .card) {
		self.style = style
		super.init(frame: .zero)
		messageLabel.text = message
		configureMessageLabel(for: style)

		layer.cornerRadius = 18
		layer.cornerCurve = .continuous
		layer.shadowColor = UIColor.black.cgColor
		layer.shadowOpacity = 0.18
		layer.shadowRadius = 8
		layer.shadowOffset = CGSize(width: 0, height: 2)

		applyTheme()

		stackView.addArrangedSubview(messageLabel)
		stackView.addArrangedSubview(closeButton)

		addSubview(stackView)

		stackView.snp.makeConstraints { make in
			make.edges.equalToSuperview()
		}

		closeButton.snp.makeConstraints { make in
			make.width.height.equalTo(28)
		}

		closeButton.addTarget(self, action: #selector(handleDismissTap), for: .touchUpInside)

		isAccessibilityElement = false
		messageLabel.isAccessibilityElement = true
		messageLabel.accessibilityTraits = .staticText
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
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
				stackView.alignment = .top
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
				layer.borderColor = HCColor.Content.border(isDark).cgColor
				let scale = traitCollection.displayScale
				layer.borderWidth = scale > 0 ? 1.0 / scale : 0.5
			case .snackbar:
				backgroundColor = HCColor.Structure.snackbarBackground(isDark)
				messageLabel.textColor = isDark ? HCColor.Text.lightModePrimary : HCColor.white
				closeButton.tintColor = isDark ? HCColor.Content.textSecondary(false) : HCColor.white.withAlphaComponent(0.7)
				layer.borderWidth = 0
		}
	}

	@objc private func handleDismissTap() {
		onDismiss?()
	}
}
