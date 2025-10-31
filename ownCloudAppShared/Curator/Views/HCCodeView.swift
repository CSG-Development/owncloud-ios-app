import UIKit

public final class BackspaceAwareTextField: UITextField {
	var onBackspace: ((String?) -> Void)?
	var onPaste: ((String) -> Void)?
	var onFocus: (() -> Void)?

	public override func deleteBackward() {
		onBackspace?(text)
	}

	public override func paste(_ sender: Any?) {
		if let s = UIPasteboard.general.string {
			onPaste?(s)
		}
	}

	public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		if action == #selector(paste(_:)) {
			return UIPasteboard.general.hasStrings
		}
		return false
	}

	public override func becomeFirstResponder() -> Bool {
		defer { onFocus?() }
		return super.becomeFirstResponder()
	}
}

public final class HCDigitBoxView: ThemeCSSView {
	public private(set) var digitTextField: BackspaceAwareTextField!

	public var isError: Bool = false {
		didSet {
			updateAppearance()
		}
	}

	public var onBackspace: ((String?) -> Void)?
	public var onPaste: ((String) -> Void)?
	public var onFocus: (() -> Void)?

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
		let textField = BackspaceAwareTextField(frame: .zero)
		textField.font = .systemFont(ofSize: 16)
		textField.textAlignment = .center
		textField.keyboardType = .numberPad
		textField.textContentType = .none
		textField.autocorrectionType = .no
		textField.autocapitalizationType = .none
		textField.borderStyle = .none
		textField.backgroundColor = .clear
		textField.spellCheckingType = .no
		textField.smartDashesType = .no
		textField.smartQuotesType = .no
		textField.smartInsertDeleteType = .no
		textField.passwordRules = nil
		if #available(iOS 17.0, *) {
			textField.inlinePredictionType = .no
		}
		let item = textField.inputAssistantItem
		item.leadingBarButtonGroups  = []
		item.trailingBarButtonGroups = []

		addSubview(textField)
		self.digitTextField = textField
		textField.snp.makeConstraints {
			$0.leading.trailing.equalToSuperview().inset(8)
			$0.top.bottom.equalToSuperview().inset(8)
		}
		textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
		textField.addTarget(self, action: #selector(editingDidBegin), for: .editingDidBegin)
		textField.addTarget(self, action: #selector(editingDidEnd), for: .editingDidEnd)

		textField.onBackspace = { [weak self] text in
			self?.onBackspace?(text)
		}
		textField.onPaste = { [weak self] text in
			self?.onPaste?(text)
		}
		textField.onFocus = { [weak self] in
			self?.onFocus?()
		}
		updateAppearance()
	}

	public override func layoutSubviews() {
		super.layoutSubviews()

		layer.cornerRadius = bounds.size.width / 2.0
	}

	public override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		updateAppearance()
	}

	@objc private func editingChanged() {
		updateAppearance()
	}

	@objc private func editingDidBegin() {
		updateAppearance()
	}

	@objc private func editingDidEnd() {
		updateAppearance()
	}

	public func clearDigit() {
		digitTextField.text = nil
	}

	private func updateAppearance() {
		let css = Theme.shared.activeCollection.css

		backgroundColor = .clear

		let textColor = css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		let activeColor = css.getColor(.stroke, selectors: [.hcDigitBox, .focused], for: nil) ?? .white
		let inactiveColor = css.getColor(.stroke, selectors: [.hcDigitBox, .plain], for: nil) ?? .white
		let errorColor = css.getColor(.stroke, selectors: [.hcDigitBox, .error], for: nil) ?? .white

		let isActive = digitTextField.isFirstResponder

		layer.borderWidth = isActive ? 3 : 1
		layer.borderColor = (isActive ? activeColor : inactiveColor).cgColor

		layer.borderColor = switch (isError, isActive) {
			case (true, _): errorColor.cgColor
			case (_, true): activeColor.cgColor
			case (_, false): inactiveColor.cgColor
		}

		digitTextField.textColor = textColor
		digitTextField.tintColor = activeColor
	}
}

public final class HCCodeView: ThemeCSSView, UITextFieldDelegate {

	private lazy var codeStack: UIStackView = {
		let stackView = UIStackView()
		stackView.axis = .horizontal
		stackView.alignment = .center
		stackView.distribution = .fillEqually
		stackView.spacing = 8
		return stackView
	}()

	private var digitContainers: [HCDigitBoxView] = []
	private var digitTextFields: [UITextField] = []
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
		addSubview(codeStack)
		codeStack.snp.makeConstraints { $0.edges.equalToSuperview() }

		buildDigitBoxes()
		updateView()
	}

	private func updateView() {
		updateDigitBorderColors(showError: isError)
		notifyChange()
	}

	private func updateDigitBorderColors(showError: Bool) {
		for box in digitContainers {
			box.isError = showError
		}
	}

	private func buildDigitBoxes() {
		digitContainers.removeAll()
		digitTextFields.removeAll()

		for i in 0..<codeLength {
			let box = HCDigitBoxView(frame: .zero)
			box.tag = i
			codeStack.addArrangedSubview(box)
			digitContainers.append(box)
			box.onBackspace = { [weak self] currentText in
				guard let self else { return }
				let isEmpty = (currentText ?? "").isEmpty
				if isEmpty {
					if i > 0 {
						self.digitTextFields[i - 1].text = ""
						_ = self.digitTextFields[i - 1].becomeFirstResponder()
					}
				} else {
					box.clearDigit()
				}
				self.notifyChange()
			}
			box.onPaste = { [weak self] str in
				self?.handlePaste(str)
			}
			box.onFocus = { [weak self] in
				self?.onFocus?()
			}
			let tf = box.digitTextField!
			tf.delegate = self
			tf.addTarget(self, action: #selector(codeEditingChanged(_:)), for: .editingChanged)
			digitTextFields.append(tf)
		}
		clearCode()
	}

	public func clearCode() {
		for tf in digitTextFields { tf.text = "" }
		notifyChange()
	}

	public func focus() {
		guard let firstField = digitTextFields.first else { return }
		firstField.becomeFirstResponder()
	}

	public func unfocus() {
		digitTextFields.forEach { $0.resignFirstResponder() }
	}

	@objc private func codeEditingChanged(_ sender: UITextField) {
		// Normalize to a single character per field and move focus when needed
		guard let index = digitTextFields.firstIndex(of: sender) else { return }
		let text = (sender.text ?? "").filter { $0.isNumber }
		if text.count > 1 {
			handlePaste(text)
			return
		}
		sender.text = String(text.prefix(1))
		if (sender.text ?? "").count == 1 {
			moveFocusForward(from: index)
		}
		notifyChange()
	}

	private func handlePaste(_ content: String) {
		let digitsOnly = content.filter { $0.isNumber }
		let limited = String(digitsOnly.prefix(codeLength))
		for tf in digitTextFields { tf.text = "" }
		for (i, ch) in limited.enumerated() {
			if i < digitTextFields.count {
				digitTextFields[i].text = String(ch)
			}
		}
		let targetIndex = min(max(limited.count, 1) - 1, digitTextFields.count - 1)
		if targetIndex >= 0 { _ = digitTextFields[targetIndex].becomeFirstResponder() }
		notifyChange()
	}

	private func moveFocusForward(from index: Int) {
		let next = index + 1
		if next < digitTextFields.count {
			_ = digitTextFields[next].becomeFirstResponder()
		}
	}

	private func moveFocusBackward(from index: Int) {
		let prev = index - 1
		if prev >= 0 {
			_ = digitTextFields[prev].becomeFirstResponder()
		}
	}

	private func notifyChange() {
		let code = digitTextFields.reduce(into: "") { result, tf in
			let t = (tf.text ?? "").filter { $0.isNumber }
			if let c = t.first { result.append(c) }
		}
		onChange?(String(code.prefix(codeLength)))
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
		guard let index = digitTextFields.firstIndex(of: textField) else { return false }
		let current = textField.text ?? ""
		guard let r = Range(range, in: current) else { return false }
		let replacement = string.filter { $0.isNumber }

		// Handle backspace when empty: move to previous field
		if replacement.isEmpty && range.length == 1 && current.isEmpty {
			if index > 0 {
				let prev = digitTextFields[index - 1]
				prev.text = ""
				_ = prev.becomeFirstResponder()
				notifyChange()
			}
			return false
		}

		// Overwrite existing digit when typing into a filled field without selection
		if !current.isEmpty && replacement.count == 1 && range.length == 0 {
			textField.text = replacement
			moveFocusForward(from: index)
			notifyChange()
			return false
		}

		// Handle paste (multiple chars) uniformly: fill from first field
		if replacement.count > 1 {
			handlePaste(replacement)
			return false
		}

		// Single-digit input or deletion within the field
		let newText = current.replacingCharacters(in: r, with: replacement)
		let filtered = newText.filter { $0.isNumber }
		if filtered.count > 1 { return false }
		if filtered.count == 1 {
			textField.text = String(filtered)
			moveFocusForward(from: index)
			notifyChange()
			return false
		}
		// Allow clearing the field
		return true
	}
}
