import UIKit

public enum HCIcon {
	public static var settings: UIImage? { sharedIcon("settings") }
	public static var arrowBack: UIImage? { sharedIcon("arrow-back") }
	public static var reset: UIImage? { sharedIcon("reset") }
	public static var device: UIImage? { sharedIcon("device-icon") }
	public static var logo: UIImage? { sharedIcon("files-logo") }

	private static func sharedIcon(_ name: String) -> UIImage? {
		UIImage(named: name, in: Bundle.sharedAppBundle, with: nil)
	}
}
