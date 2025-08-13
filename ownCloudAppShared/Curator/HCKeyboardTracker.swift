import UIKit

public final class HCKeyboardTracker {
	public static let shared = HCKeyboardTracker()

	public enum State {
		case dispalyed, hidden, showing, hiding
	}

	public private(set) var state: State = .hidden

	public init() {
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillShow),
			name: UIResponder.keyboardWillShowNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardDidShow),
			name: UIResponder.keyboardDidShowNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillHide),
			name: UIResponder.keyboardWillHideNotification,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardDidHide),
			name: UIResponder.keyboardDidHideNotification,
			object: nil
		)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc
	private func keyboardWillShow() {
		state = .showing
	}

	@objc
	private func keyboardDidShow() {
		state = .dispalyed
	}

	@objc
	private func keyboardWillHide() {
		state = .hiding
	}

	@objc
	private func keyboardDidHide() {
		state = .hidden
	}
}
