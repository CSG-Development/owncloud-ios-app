import UIKit
import SnapKit
import ownCloudApp

final class PasscodeLandscapeView: ThemeCSSView {
	let titleLabel = UILabel()
	let subtitleLabel = UILabel()
	let passcodeLabel = UILabel()
	let errorLabel = UILabel()
	let timeoutLabel = UILabel()
	let codePad = HCCodePadView(frame: .zero)

	private var labelsStack: UIStackView!
	private var rightColumn: UIView!

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

		labelsStack = UIStackView(arrangedSubviews: [
			titleLabel,
			subtitleLabel,
			passcodeLabel,
			errorLabel
		])
		labelsStack.axis = .vertical
		labelsStack.alignment = .center
		labelsStack.spacing = 12

		let leftColumn = UIView()
		leftColumn.addSubview(labelsStack)
		labelsStack.snp.makeConstraints {
			$0.top.equalToSuperview().offset(24)
			$0.centerX.equalToSuperview()
			$0.leading.greaterThanOrEqualToSuperview().offset(16)
			$0.trailing.lessThanOrEqualToSuperview().inset(16)
			$0.bottom.lessThanOrEqualToSuperview()
		}

		leftColumn.addSubview(timeoutLabel)
		timeoutLabel.snp.makeConstraints {
			$0.center.equalToSuperview()
			$0.leading.greaterThanOrEqualToSuperview().offset(16)
			$0.trailing.lessThanOrEqualToSuperview().inset(16)
		}
		timeoutLabel.isHidden = true

		rightColumn = UIView()
		rightColumn.addSubview(codePad)
		codePad.snp.makeConstraints {
			$0.center.equalToSuperview()
			$0.top.greaterThanOrEqualToSuperview().offset(17)
			$0.bottom.lessThanOrEqualToSuperview().inset(17)
			$0.leading.greaterThanOrEqualToSuperview()
			$0.trailing.lessThanOrEqualToSuperview()
			$0.height.lessThanOrEqualToSuperview().offset(-34)
			$0.height.equalToSuperview().offset(-34).priority(.high)
			$0.width.lessThanOrEqualTo(236)
		}

		let hStack = UIStackView(arrangedSubviews: [leftColumn, rightColumn])
		hStack.axis = .horizontal
		hStack.distribution = .fillEqually
		hStack.spacing = 24

		addSubview(hStack)
		hStack.snp.makeConstraints {
			$0.edges.equalToSuperview()
		}
	}

	// MARK: - Timeout

	func setTimeoutActive(_ active: Bool) {
		isTimedOut = active
		codePad.isHidden = active
		rightColumn.isUserInteractionEnabled = !active
		timeoutLabel.isHidden = !active
		applyLabelColors()
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
