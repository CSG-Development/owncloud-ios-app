import Foundation
import ownCloudSDK

// Deprecated shim. Forward to DeviceReachabilityURLProvider to preserve compatibility.
@objcMembers
public final class URLResolverBridge: NSObject, OCBaseURLProvider {
	public static let shared = URLResolverBridge()
	@objc(currentBaseURLForConnection:)
	public func currentBaseURL(for connection: OCConnection) -> URL? {
		return DeviceReachabilityURLProvider.shared.currentBaseURL(for: connection)
	}
}

import Foundation
import ownCloudSDK

// Deprecated shim. Forward to DeviceReachabilityURLProvider to preserve compatibility.
@objcMembers
public final class URLResolverBridge: NSObject, OCBaseURLProvider {
	public static let shared = URLResolverBridge()
	@objc(currentBaseURLForConnection:)
	public func currentBaseURL(for connection: OCConnection) -> URL? {
		return DeviceReachabilityURLProvider.shared.currentBaseURL(for: connection)
	}
}
