import UIKit

extension UIView {
	public func findAndResignFirstResponder() {
		if isFirstResponder {
			resignFirstResponder()
		}
		for subview in subviews {
			subview.findAndResignFirstResponder()
		}
	}
}
