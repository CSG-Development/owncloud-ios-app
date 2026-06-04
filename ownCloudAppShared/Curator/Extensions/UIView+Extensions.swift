import UIKit

extension UIView {
	public var subviewsRecursive: [UIView] {
		subviews + subviews.flatMap(\.subviewsRecursive)
	}

	public func findAndResignFirstResponder() {
		if isFirstResponder {
			resignFirstResponder()
		}
		for subview in subviews {
			subview.findAndResignFirstResponder()
		}
	}
}
