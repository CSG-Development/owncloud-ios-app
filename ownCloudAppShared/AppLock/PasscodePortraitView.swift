import UIKit
import SnapKit
import ownCloudApp

final class PasscodePortraitView: ThemeCSSView {
	let titleLabel = UILabel()
	let subtitleLabel = UILabel()
	let passcodeLabel = UILabel()
	let errorLabel = UILabel()
	let timeoutLabel = UILabel()
	let codePad = HCCodePadView(frame: .zero)

	private var combinedStack: UIStackView!
	private var centerYConstraint: Constraint?
	private var topConstraint: Constraint?

	private var isTimedOut = false
	private var normalTextColor: UIColor = .white
	private var errorColor: UIColor?

	override init(frame: CGRect) {
		super.init(frame: frame)
		setupUI()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupUI()
	}

	private func setupUI() {
		configureTitleLabel(titleLabel)
		configureSubtitleLabel(subtitleLabel)
		configurePasscodeLabel(passcodeLabel)
		configureErrorLabel(errorLabel)
		configureTimeoutLabel(timeoutLabel)

		let labelsStack = UIStackView(arrangedSubviews: [
			titleLabel,
			subtitleLabel,
			passcodeLabel,
			errorLabel
		])
		labelsStack.axis = .vertical
		labelsStack.alignment = .center
		labelsStack.spacing = 12

		codePad.snp.makeConstraints {
			$0.width.lessThanOrEqualTo(236)
			$0.width.equalTo(236).priority(.high)
		}

		combinedStack = UIStackView(arrangedSubviews: [
			labelsStack,
			HCSpacerView(40, .vertical),
			codePad
		])
		combinedStack.axis = .vertical
		combinedStack.alignment = .center
		combinedStack.spacing = 0

		addSubview(combinedStack)
		combinedStack.snp.makeConstraints {
			centerYConstraint = $0.centerY.equalToSuperview().constraint
			topConstraint = $0.top.equalToSuperview().offset(24).constraint
			$0.centerX.equalToSuperview()
			$0.leading.greaterThanOrEqualToSuperview().offset(16)
			$0.trailing.lessThanOrEqualToSuperview().inset(16)
			$0.top.greaterThanOrEqualToSuperview()
			$0.bottom.lessThanOrEqualToSuperview()
		}
		topConstraint?.deactivate()

		timeoutLabel.isHidden = true
		addSubview(timeoutLabel)
		timeoutLabel.snp.makeConstraints {
			$0.center.equalToSuperview()
			$0.leading.greaterThanOrEqualToSuperview().offset(16)
			$0.trailing.lessThanOrEqualToSuperview().inset(16)
		}
	}

	// MARK: - Timeout

	func setTimeoutActive(_ active: Bool) {
		isTimedOut = active
		codePad.isHidden = active
		timeoutLabel.isHidden = !active
		applyLabelColors()

		if active {
			centerYConstraint?.deactivate()
			topConstraint?.activate()
		} else {
			topConstraint?.deactivate()
			centerYConstraint?.activate()
		}
	}

	private func applyLabelColors() {
		let color: UIColor = isTimedOut ? .gray : normalTextColor
		titleLabel.textColor = color
		subtitleLabel.textColor = color
		passcodeLabel.textColor = color
		errorLabel.textColor = isTimedOut ? .gray : errorColor
	}

	// MARK: - Label configuration

	private func configureTitleLabel(_ label: UILabel) {
		label.numberOfLines = 0
		label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
		label.textAlignment = .center
		label.text = "Please enter your passcode"
	}

	private func configureSubtitleLabel(_ label: UILabel) {
		label.numberOfLines = 0
		label.font = UIFont.systemFont(ofSize: 14)
		label.textAlignment = .center
		label.text = ""
	}

	private func configurePasscodeLabel(_ label: UILabel) {
		label.numberOfLines = 1
		label.font = UIFont.systemFont(ofSize: 17, weight: .medium)
		label.textAlignment = .center
		label.cssSelector = .code
	}

	private func configureErrorLabel(_ label: UILabel) {
		label.numberOfLines = 0
		label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
		label.textAlignment = .center
		label.minimumScaleFactor = 0.5
		label.adjustsFontSizeToFitWidth = true
	}

	private func configureTimeoutLabel(_ label: UILabel) {
		label.numberOfLines = 0
		label.font = UIFont.systemFont(ofSize: 17, weight: .medium)
		label.textAlignment = .center
	}

	// MARK: - Theming

	override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		errorColor = collection.css.getColor(.stroke, selectors: [.primary_auth, .error], for: nil)

		normalTextColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		timeoutLabel.textColor = normalTextColor
		applyLabelColors()
	}
}
