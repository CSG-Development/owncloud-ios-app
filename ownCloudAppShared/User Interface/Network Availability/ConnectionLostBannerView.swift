import UIKit
import SnapKit
import ownCloudSDK

/// Persistent bottom snackbar shown when the Home Cloud device host is unreachable.
/// Stays visible until connectivity is restored or Retry succeeds.
public final class ConnectionLostBannerView: UIView {
	public var onRetry: (() -> Void)?

	private let stackView: UIStackView = {
		let stack = UIStackView()
		stack.axis = .horizontal
		stack.alignment = .center
		stack.spacing = 12
		stack.isLayoutMarginsRelativeArrangement = true
		stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
		return stack
	}()

	private let messageLabel: UILabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: 14, weight: .medium)
		label.numberOfLines = 0
		label.lineBreakMode = .byWordWrapping
		label.setContentHuggingPriority(.defaultLow, for: .horizontal)
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		return label
	}()

	private let retryButton: UIButton = {
		let button = UIButton(type: .system)
		button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
		button.setContentHuggingPriority(.required, for: .horizontal)
		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		return button
	}()

	public init(message: String, retryTitle: String) {
		super.init(frame: .zero)
		messageLabel.text = message
		retryButton.setTitle(retryTitle, for: .normal)

		layer.cornerRadius = 4
		layer.cornerCurve = .continuous
		applyTheme()

		stackView.addArrangedSubview(messageLabel)
		stackView.addArrangedSubview(retryButton)
		addSubview(stackView)

		stackView.snp.makeConstraints { make in
			make.edges.equalToSuperview()
		}

		retryButton.addTarget(self, action: #selector(handleRetryTap), for: .touchUpInside)

		isAccessibilityElement = false
		messageLabel.isAccessibilityElement = true
		messageLabel.accessibilityTraits = .staticText
		retryButton.isAccessibilityElement = true
		retryButton.accessibilityTraits = .button
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

	private func applyTheme() {
		let isDark = traitCollection.userInterfaceStyle == .dark
		backgroundColor = HCColor.Structure.snackbarBackground(isDark)
		messageLabel.textColor = HCColor.Content.textPrimaryInverted(isDark)
		retryButton.tintColor = HCColor.Interaction.primarySolidNormalInverted(isDark)
	}

	@objc private func handleRetryTap() {
		onRetry?()
	}
}
