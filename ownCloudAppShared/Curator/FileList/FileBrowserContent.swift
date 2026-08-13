import UIKit
import ownCloudSDK

/// Shared surface for browser host chrome (location bar, root detection) across
/// folder browse (`FileListViewController`) and legacy lists (`ClientItemViewController`).
public protocol FileBrowserContent: AnyObject {
	var clientContext: ClientContext? { get }
	var location: OCLocation? { get }
	var query: OCQuery? { get }
}
