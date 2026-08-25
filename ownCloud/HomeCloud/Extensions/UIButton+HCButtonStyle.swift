import UIKit
import ownCloudAppShared

extension UIButton {
	func setTitle(title: String, style: HCButtonStyle, darkMode: Bool) {
		applyHCButtonStyle(title: title, style: style, isDark: darkMode)
	}
}
