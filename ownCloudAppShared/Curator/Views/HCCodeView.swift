import UIKit

public final class HCDigitBoxView: ThemeCSSView {
	private(set) var digitLabel: UILabel!

	public var isActive: Bool = false {
		didSet {
			updateView()
		}
	}

	public var isError: Bool = false {
		didSet {
			updateView()
		}
	}

	public override init(frame: CGRect) {
		super.init(frame: frame)

		setupView()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)

		setupView()
	}

	private func setupView() {
		snp.makeConstraints { make in
			make.width.equalTo(40)
			make.height.equalTo(56)
		}
		let digitLabel = UILabel()
		digitLabel.font = .systemFont(ofSize: 16)
		digitLabel.textAlignment = .center
		addSubview(digitLabel)
		self.digitLabel = digitLabel
		digitLabel.snp.makeConstraints {
			$0.center.equalToSuperview()
		}
		updateView()
	}

	public override func layoutSubviews() {
		super.layoutSubviews()

		layer.cornerRadius = bounds.size.width / 2.0
	}

	private func updateView() {
		let css = Theme.shared.activeCollection.css

		let activeColor = css.getColor(.stroke, selectors: [.hcDigitBox, .focused], for: nil) ?? .white
		let inactiveColor = css.getColor(.stroke, selectors: [.hcDigitBox, .plain], for: nil) ?? .white
		let errorColor = css.getColor(.stroke, selectors: [.hcDigitBox, .error], for: nil) ?? .white

		layer.borderWidth = isActive ? 3 : 1
		layer.borderColor = (isActive ? activeColor : inactiveColor).cgColor

		layer.borderColor = switch (isError, isActive) {
			case (true, _): errorColor.cgColor
			case (_, true): activeColor.cgColor
			case (_, false): inactiveColor.cgColor
		}

		digitLabel.textColor = css.getColor(.stroke, selectors: [.text], for: nil) ?? .white
	}

	public override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		updateView()
	}
}

public final class HCCodeView: ThemeCSSView, UITextFieldDelegate {
	private lazy var hiddenCodeField: UITextField = {
		let textField = UITextField(frame: .zero)
		textField.keyboardType = .numberPad
		textField.textContentType = .oneTimeCode
		textField.autocorrectionType = .no
		textField.autocapitalizationType = .none
		textField.delegate = self
		textField.isHidden = true
		textField.addTarget(self, action: #selector(codeEditingChanged), for: .editingChanged)
		return textField
	}()

	private lazy var codeStack: UIStackView = {
		let stackView = UIStackView()
		stackView.axis = .horizontal
		stackView.alignment = .center
		stackView.distribution = .fillEqually
		stackView.spacing = 8
		return stackView
	}()

	private var digitContainers: [HCDigitBoxView] = []
	private var digitLabels: [UILabel] = []
	private let codeLength: Int

	public var isError: Bool = false {
		didSet {
			updateView()
		}
	}

	public var onChange: ((String) -> Void)?
	public var onFocus: (() -> Void)?

	public init(codeLength: Int) {
		self.codeLength = codeLength
		super.init(frame: .zero)

		setupView()
	}

	required init?(coder: NSCoder) {
		fatalError("Not implemented.")
	}

	private func setupView() {
		addSubview(hiddenCodeField)
		hiddenCodeField.snp.makeConstraints { $0.edges.equalToSuperview() }

		addSubview(codeStack)
		codeStack.snp.makeConstraints { $0.edges.equalToSuperview() }

		buildDigitBoxes()

		let tap = UITapGestureRecognizer(target: self, action: #selector(focus))
		codeStack.addGestureRecognizer(tap)

		updateView()
	}

	private func updateView() {
		updateDigitBorderColors(showError: isError)
		updateDigitLabels(with: hiddenCodeField.text ?? "")
	}

	private func updateDigitBorderColors(showError: Bool) {
		for box in digitContainers {
			box.isError = showError
		}
	}

	private func buildDigitBoxes() {
		digitContainers.removeAll()
		digitLabels.removeAll()

		for i in 0..<codeLength {
			let box = HCDigitBoxView(frame: .zero)
			box.tag = i
			codeStack.addArrangedSubview(box)
			digitContainers.append(box)
			digitLabels.append(box.digitLabel)
		}
		updateDigitLabels(with: "")
	}

	private func updateDigitLabels(with text: String) {
		for (i, label) in digitLabels.enumerated() {
			if i < text.count {
				let idx = text.index(text.startIndex, offsetBy: i)
				label.text = String(text[idx])
			} else {
				label.text = ""
			}
		}

		for (i, container) in digitContainers.enumerated() {
			let containerIsActive = i == max(0, text.count - 1)
			container.isActive = containerIsActive && hiddenCodeField.isFirstResponder
		}
	}

	public func clearCode() {
		hiddenCodeField.text = ""
		updateDigitLabels(with: "")
	}

	@objc public func focus() {
		hiddenCodeField.becomeFirstResponder()
		updateDigitLabels(with: hiddenCodeField.text ?? "")
		onFocus?()
	}

	@objc public func unfocus() {
		_ = hiddenCodeField.resignFirstResponder()
		updateDigitLabels(with: hiddenCodeField.text ?? "")
	}

	@objc private func codeEditingChanged() {
		let filtered = (hiddenCodeField.text ?? "").filter { $0.isNumber }
		let limited = String(filtered.prefix(codeLength))
		if hiddenCodeField.text != limited { hiddenCodeField.text = limited }
		updateDigitLabels(with: limited)
		onChange?(limited)
	}

	public override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)
		backgroundColor = .clear

		updateView()
	}

	public func textField(
		_ textField: UITextField,
		shouldChangeCharactersIn range: NSRange,
		replacementString string: String
	) -> Bool {
		let current = textField.text ?? ""
		guard let r = Range(range, in: current) else { return false }

		let newText = current.replacingCharacters(in: r, with: string)
		let filtered = newText.filter { $0.isNumber }

		return filtered.count <= codeLength && filtered == newText
	}
}
