import Foundation

private let _sharedAppBundle = Bundle(identifier: "com.seagate.owncloud.homeCloudAppShared")

public extension Bundle {
	static var hcSharedAppBundle: Bundle {
		_sharedAppBundle!
	}
}
