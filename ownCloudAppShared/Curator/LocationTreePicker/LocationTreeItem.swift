import ownCloudSDK
import Foundation
import UIKit

struct LocationTreeItem: Hashable {
	let id: OCPath
	var title: String
	var icon: UIImage?
	var depth: Int
	var isExpandable: Bool
	var isExpanded: Bool
	var isLoading: Bool

	func hash(into hasher: inout Hasher) { hasher.combine(id) }

	static func == (l: Self, r: Self) -> Bool { l.id == r.id }
}
