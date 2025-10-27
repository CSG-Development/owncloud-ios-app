import UIKit

public enum HCIcon {
	public static var settings: UIImage? { sharedIcon("settings") }
	public static var arrowBack: UIImage? { sharedIcon("arrow-back") }
	public static var reset: UIImage? { sharedIcon("reset") }

	private static func sharedIcon(_ name: String) -> UIImage? {
		UIImage(named: name, in: Bundle.sharedAppBundle, with: nil)
	}
}
