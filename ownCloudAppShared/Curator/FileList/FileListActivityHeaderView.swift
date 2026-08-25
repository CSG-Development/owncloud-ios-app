import SnapKit
import UIKit

/// Fixed header band for the Activity-in-progress card (info icon, title, subtitle, progress, chevron).
final class FileListActivityHeaderView: UIView {

	static let horizontalInset: CGFloat = 16
	static let verticalInset: CGFloat = 16
	static let contentSpacing: CGFloat = 16
	static let progressHeight: CGFloat = 4
	private static let titleSubtitleSpacing: CGFloat = 4
	private static let subtitleProgressSpacing: CGFloat = 8
	private static let titleHeight: CGFloat = 22
	private static let subtitleHeight: CGFloat = 16

	static func preferredHeight(expanded: Bool = false) -> CGFloat {
		let contentHeight = titleHeight
			+ titleSubtitleSpacing
			+ subtitleHeight
			+ subtitleProgressSpacing
			+ progressHeight
		return (verticalInset * 2) + contentHeight
	}

	var onToggleExpanded: (() -> Void)?

	private let infoIconView = UIImageView()
	private let contentStack = UIStackView()
	private let titleLabel = UILabel()
	private let subtitleLabel = UILabel()
	private let progressView = UIProgressView(progressViewStyle: .default)
	private let chevronButton = UIButton(type: .system)
	private let headerButton = UIButton(type: .custom)
	private var isExpanded = false
	private var isDark = false

	override init(frame: CGRect) {
		super.init(frame: frame)

		setContentCompressionResistancePriority(.required, for: .vertical)
		setContentHuggingPriority(.required, for: .vertical)

		infoIconView.contentMode = .scaleAspectFit
		infoIconView.image = HCIcon.info?.withRenderingMode(.alwaysTemplate)
		infoIconView.setContentHuggingPriority(.required, for: .horizontal)
		infoIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
		infoIconView.isUserInteractionEnabled = false

		contentStack.axis = .vertical
		contentStack.alignment = .fill
		contentStack.distribution = .fill
		contentStack.isUserInteractionEnabled = false

		titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
		titleLabel.numberOfLines = 1
		titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		titleLabel.setContentHuggingPriority(.required, for: .vertical)

		subtitleLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
		subtitleLabel.numberOfLines = 1
		subtitleLabel.setContentHuggingPriority(.required, for: .vertical)

		progressView.progress = 0
		progressView.setContentHuggingPriority(.required, for: .vertical)

		chevronButton.contentMode = .scaleAspectFit
		chevronButton.setImage(HCIcon.chevronDownLarge?.withRenderingMode(.alwaysTemplate), for: .normal)
		chevronButton.setContentHuggingPriority(.required, for: .horizontal)
		chevronButton.setContentCompressionResistancePriority(.required, for: .horizontal)
		chevronButton.addTarget(self, action: #selector(headerTapped), for: .touchUpInside)

		headerButton.accessibilityTraits = [.button, .header]
		headerButton.backgroundColor = .clear
		headerButton.addTarget(self, action: #selector(headerTapped), for: .touchUpInside)

		contentStack.addArrangedSubview(titleLabel)
		contentStack.addArrangedSubview(subtitleLabel)
		contentStack.addArrangedSubview(progressView)

		addSubview(headerButton)
		addSubview(infoIconView)
		addSubview(contentStack)
		addSubview(chevronButton)

		contentStack.snp.makeConstraints {
			$0.leading.equalTo(infoIconView.snp.trailing).offset(Self.contentSpacing)
			$0.trailing.equalTo(chevronButton.snp.leading).offset(-Self.contentSpacing)
			$0.top.bottom.equalToSuperview().inset(Self.verticalInset)
		}

		infoIconView.snp.makeConstraints {
			$0.leading.equalToSuperview().inset(Self.horizontalInset)
			$0.centerY.equalTo(contentStack)
			$0.size.equalTo(24)
		}

		chevronButton.snp.makeConstraints {
			$0.trailing.equalToSuperview().inset(Self.horizontalInset)
			$0.centerY.equalTo(contentStack)
			$0.size.equalTo(24)
		}

		progressView.snp.makeConstraints {
			$0.height.equalTo(Self.progressHeight)
		}

		contentStack.setCustomSpacing(4, after: titleLabel)
		contentStack.setCustomSpacing(8, after: subtitleLabel)

		headerButton.snp.makeConstraints {
			$0.top.leading.bottom.equalToSuperview()
			$0.trailing.equalTo(chevronButton.snp.leading)
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(
		operationCount: Int,
		combinedProgress: Float,
		expanded: Bool,
		animated: Bool = false
	) {
		let expansionChanged = isExpanded != expanded
		isExpanded = expanded

		titleLabel.text = HCL10n.ZipAction.Activity.title
		subtitleLabel.text = String(format: HCL10n.ZipAction.Activity.operationsInProgressFormat, operationCount)
		setProgress(combinedProgress)

		let accessibilityText = [titleLabel.text, subtitleLabel.text].compactMap { $0 }.joined(separator: ", ")
		headerButton.accessibilityLabel = accessibilityText
		chevronButton.accessibilityLabel = accessibilityText

		updateChevronImage(expanded: expanded, animated: animated && expansionChanged)
		updateProgressVisibility(expanded: expanded, animated: animated && expansionChanged)
	}

	func applyColors(isDark: Bool) {
		self.isDark = isDark
		let titleColor = HCColor.Content.textPrimary(isDark)
		titleLabel.textColor = titleColor
		subtitleLabel.textColor = titleColor

		let iconColor = HCColor.Interaction.buttonsPrimarySolidOutlined(isDark)
		infoIconView.tintColor = iconColor
		chevronButton.tintColor = iconColor

		progressView.progressTintColor = HCColor.Interaction.cta(isDark)
		progressView.trackTintColor = HCColor.Content.border2(isDark)
	}

	@objc private func headerTapped() {
		onToggleExpanded?()
	}

	private func updateChevronImage(expanded: Bool, animated: Bool) {
		let image = (expanded ? HCIcon.chevronUpLarge : HCIcon.chevronDownLarge)?
			.withRenderingMode(.alwaysTemplate)
		guard animated else {
			chevronButton.setImage(image, for: .normal)
			return
		}
		UIView.transition(with: chevronButton, duration: 0.28, options: [.transitionCrossDissolve, .allowUserInteraction]) {
			self.chevronButton.setImage(image, for: .normal)
		}
	}

	private func updateProgressVisibility(expanded: Bool, animated: Bool) {
		let showProgress = !expanded
		progressView.isHidden = false
		progressView.accessibilityElementsHidden = expanded

		guard animated else {
			progressView.alpha = showProgress ? 1 : 0
			return
		}

		UIView.animate(
			withDuration: 0.28,
			delay: 0,
			options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
		) {
			self.progressView.alpha = showProgress ? 1 : 0
		}
	}

	private func setProgress(_ value: Float) {
		if abs(progressView.progress - value) > 0.001 {
			progressView.setProgress(value, animated: value > progressView.progress)
		} else {
			progressView.progress = value
		}
	}
}
