import Combine
import Foundation
import ownCloudSDK

protocol LocationTreeRepository {
	/// Hot stream for a single node. Must emit the current snapshot immediately on subscribe.
	func observeNode(_ id: OCPath) -> AnyPublisher<LocationTreeNode, Never>

	/// Idempotent command: if node is idle/failed, transition to loading and eventually publish loaded.
	func ensureNode(_ id: OCPath)

	/// Convenience to satisfy “open mid-tree”: preload children for anchor and all ancestors up to root.
	func warmChainToRoot(from anchorID: OCPath)

	func currentNode(_ id: OCPath) -> LocationTreeNode?
}
