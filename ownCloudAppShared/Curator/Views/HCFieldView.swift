import UIKit
import SnapKit

extension ThemeCSSSelector {
	public static let hcField = ThemeCSSSelector(rawValue: "hcField")
}

open class HCFieldView: ThemeCSSView {
	private enum Constants {
		static let errorLabelFontSize = 12.0
		static let errorLabelSpacing = 4.0
	}

	private var borderColor: UIColor?
	private var focusedBorderColor: UIColor?
	private var errorColor: UIColor?
	private var titleColor: UIColor?

	private var borderWidth: CGFloat = 1
	private var focusedBorderWidth: CGFloat = 1

	private lazy var errorLabel: UILabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: Constants.errorLabelFontSize)
		label.textColor = errorColor
		label.numberOfLines = 0
		label.alpha = 0
		return label
	}()

	public let borderView = HCBorderView()

	public var errorText: String? {
		didSet {
			errorLabel.text = errorText
			UIView.animate(withDuration: 0.25) {
				self.errorLabel.alpha = (self.errorText?.isEmpty ?? true) ? 0 : 1
			}
			updateAppearance()
		}
	}

	private var floatingLabelColor: UIColor? {
		focusedBorderColor
	}

	public var isActive: Bool {
		fatalError("Not implemented")
	}

	public var contentView: UIView {
		fatalError("Not implemented")
	}

	public override init(frame: CGRect) {
		super.init(frame: frame)

		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)

		commonInit()
	}

	private func commonInit() {
		cssSelectors = (cssSelectors ?? []) + [.hcField]

		borderView.snp.makeConstraints {
			$0.height.equalTo(56)
		}
		borderView.addSubview(contentView)

		contentView.snp.makeConstraints {
			$0.top.equalToSuperview().offset(16)
			$0.left.equalToSuperview().offset(16)
			$0.bottom.equalToSuperview().offset(-16)
			$0.right.equalToSuperview().offset(-16)
		}

		let stackView = UIStackView()
		stackView.axis = .vertical
		stackView.spacing = 0
		stackView.addArrangedSubview(borderView)

		let errorLabelContainer = UIView()
		errorLabelContainer.backgroundColor = .clear
		errorLabelContainer.addSubview(errorLabel)
		errorLabel.snp.makeConstraints {
			$0.bottom.equalToSuperview()
			$0.top.equalToSuperview().offset(Constants.errorLabelSpacing)
			$0.leading.equalToSuperview().offset(16)
			$0.trailing.equalToSuperview().offset(-16)
		}
		errorLabelContainer.snp.makeConstraints {
			$0.height.greaterThanOrEqualTo(20)
		}

		stackView.addArrangedSubview(errorLabelContainer)

		addSubview(stackView)
		stackView.snp.makeConstraints {
			$0.edges.equalToSuperview()
		}
	}

	open func updateContentView() {
		// To override
	}

	public func updateAppearance() {
		let hasError = errorText != nil
		let borderColor = hasError ? errorColor : (isActive ? focusedBorderColor : borderColor)
		let titleColor = hasError ? errorColor : (isActive ? focusedBorderColor : titleColor)

		updateContentView()

		tintColor = focusedBorderColor

		errorLabel.textColor = errorColor

		borderView.borderColor = borderColor
		borderView.titleColor = titleColor
		borderView.borderWidth = isActive ? focusedBorderWidth : borderWidth
	}

	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		borderColor = collection.css.getColor(.stroke, selectors: [], for: self)
		focusedBorderColor = collection.css.getColor(.stroke, selectors: [.selected], for: self)
		errorColor = collection.css.getColor(.stroke, selectors: [.error], for: self)
		borderWidth = collection.css.getCGFloat(.borderWidth, selectors: [], for: self) ?? 1
		focusedBorderWidth = collection.css.getCGFloat(.borderWidth, selectors: [.selected], for: self) ?? 1
		titleColor = collection.css.getColor(.stroke, selectors: [.text], for: self)

		updateAppearance()

		super.applyThemeCollection(theme: theme, collection: collection, event: event)
	}
}
