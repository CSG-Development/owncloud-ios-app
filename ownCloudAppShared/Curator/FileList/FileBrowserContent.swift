import UIKit
import ownCloudSDK

/// Shared surface for browser host chrome (location bar, root detection) across
/// folder browse (`FileListViewController`) and legacy lists (`ClientItemViewController`).
public protocol FileBrowserContent: AnyObject {
	var clientContext: ClientContext? { get }
	var location: OCLocation? { get }
	var query: OCQuery? { get }
}

enum FileBrowserFactory {
	/// Location picker (and other modals) clear `browserController` and need the legacy list,
	/// whose query is bound at init. The main browser uses `FileListViewController`.
	static func makeViewController(
		context: ClientContext,
		query: OCQuery?,
		location: OCLocation?,
		highlightItemReference: OCDataItemReference? = nil
	) -> UIViewController {
		if context.browserController != nil {
			return FileListViewController(context: context, query: query, location: location, highlightItemReference: highlightItemReference)
		}
		return ClientItemViewController(context: context, query: query, location: location, highlightItemReference: highlightItemReference)
	}
}
