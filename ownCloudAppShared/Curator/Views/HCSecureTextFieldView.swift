import UIKit

public final class HCSecureTextFieldView: HCTextFieldView {
	private lazy var secureEntryButton: UIButton = {
		let button = UIButton(type: .custom)
		button.setImage(UIImage(systemName: "eye"), for: .normal)
		button.setImage(UIImage(systemName: "eye.slash"), for: .selected)
		button.addTarget(self, action: #selector(togglePasswordVisibility(_:)), for: .touchUpInside)
		return button
	}()

	public override init(frame: CGRect) {
		super.init(frame: frame)

		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)

		commonInit()
	}

	private func commonInit() {
		textField.rightView = secureEntryButton
		textField.rightViewMode = .always
		textField.isSecureTextEntry = true
	}

	@objc private func togglePasswordVisibility(_ sender: UIButton) {
		sender.isSelected.toggle()
		textField.isSecureTextEntry.toggle()
	}

	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		let secureEntryButtonColor = collection.css.getColor(.stroke, selectors: [.text], for: self)
		secureEntryButton.tintColor = secureEntryButtonColor

		super.applyThemeCollection(theme: theme, collection: collection, event: event)
	}
}
