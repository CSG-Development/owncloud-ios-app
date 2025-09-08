import ownCloudSDK
import Combine
import UIKit

final class LocationTreeViewModel: ObservableObject {
	private let repository: any LocationTreeRepository
	private let anchorID: OCPath
	private let rootID: OCPath

	@Published private(set) var items: [LocationTreeItem] = []

	// Flattened view state
	private var itemsByID: [OCPath: LocationTreeItem] = [:]
	private var visibleIDs: [OCPath] = []
	private var expanded: Set<OCPath> = []

	private var nodeCancellables: [OCPath: AnyCancellable] = [:]
	private var pendingChildren: [OCPath: [OCPath]] = [:]	

	@inline(__always)
	private static func norm(_ p: OCPath) -> OCPath {
		var s = ((p as String) as NSString).standardizingPath
		if s.isEmpty { s = "/" }
		if s != "/" && !s.hasSuffix("/") { s += "/" }
		return (s as NSString) as OCPath
	}

	init(repository: any LocationTreeRepository, anchorID: OCPath) {
		self.repository = repository
		self.anchorID = Self.norm(anchorID)

		let chain = Self.chainFromRoot(to: self.anchorID)         // already returns normalized elements
		self.rootID = chain.first ?? self.anchorID

		repository.warmChainToRoot(from: self.anchorID)

		visibleIDs = [rootID]
		expanded.formUnion(chain)

		let rootTitle = repository.currentNode(rootID)?.title ?? "Root"
		itemsByID[rootID] = LocationTreeItem(
			id: rootID, title: rootTitle, depth: 0,
			isExpandable: true, isExpanded: true, isLoading: true
		)
		publish()

		for id in chain {
			observeNode(id)                // id is already normalized
			repository.ensureNode(id)
		}
	}

	/// Returns [root, …, anchor], with trailing "/" on every non-root element.
	private static func chainFromRoot(to anchor: OCPath) -> [OCPath] {
		var chain: [OCPath] = []
		var seen = Set<String>()
		var cur: OCPath = Self.norm(anchor)

		while true {
			let key = cur as String
			// stop on cycles (paranoia)
			if !seen.insert(key).inserted { break }
			chain.append(cur)
			if key == "/" { break }

			// Go up one level, then normalize *back* to a directory path (re-add "/")
			let parentNoSlash = (key as NSString).deletingLastPathComponent
			let parent = Self.norm((parentNoSlash as NSString) as OCPath)

			if parent as String == key { break } // safety
			cur = parent
		}

		return chain.reversed() // [root, …, anchor]
	}

	public func toggleExpand(id raw: OCPath) {
		let id = Self.norm(raw)
		guard var item = itemsByID[id] else { return }
		// Ignore taps during loading
		if item.isLoading { return }

		if item.isExpanded {
			// Collapse
			item.isExpanded = false
			itemsByID[id] = item
			expanded.remove(id)

			// Remove subtree rows and cancel their subscriptions
			removeSubtree(of: id, onRemove: { [weak self] childID in
				self?.nodeCancellables[childID]?.cancel()
				self?.nodeCancellables[childID] = nil
			}, clearExpanded: true)
			publish()
		} else {
			// Expand
			item.isExpanded = true
			item.isLoading = true   // UI shows spinner until node emits loaded/failed
			itemsByID[id] = item
			expanded.insert(id)

			// Make sure we observe & load this node
			observeNode(id)
			repository.ensureNode(id)
			// If already loaded, splice immediately and subscribe children; otherwise keep spinner
			if let snap = repository.currentNode(id) {
				if let kids = snap.childrenIDs {
					spliceChildren(of: id, parentDepth: item.depth, childIDs: kids)
					for cid in kids { observeNode(cid) }
				}
				// Update loading flag to reflect actual node state
				if var ii = itemsByID[id] {
					let isLoadingNow: Bool = {
						if case .loading = snap.state { return true }
						return false
					}()
					ii.isLoading = isLoadingNow
					itemsByID[id] = ii
				}
			}
			publish()
		}
	}

	private func observeNode(_ id: OCPath) {
		guard nodeCancellables[id] == nil else { return }

		nodeCancellables[id] = repository.observeNode(id)
			.removeDuplicates(by: { a, b in
				// Avoid churn if nothing that affects rows changed
				a.title == b.title &&
				a.statusKey == b.statusKey &&
				a.childrenIDs == b.childrenIDs
			})
			.receive(on: DispatchQueue.main)
			.sink { [weak self] node in
				self?.apply(node: node)
			}
	}

	deinit {
		for (_, c) in nodeCancellables { c.cancel() }
		nodeCancellables.removeAll()
	}

	// Apply a node snapshot to our flattened rows
	private func apply(node: LocationTreeNode) {
		// (recommended) normalize ids here if needed
		let nid  = Self.norm(node.id)
		let pid  = node.parentID.map(Self.norm)
		let kids = node.childrenIDs?.map(Self.norm)

		let depth = itemsByID[nid]?.depth
			?? (nid == rootID ? 0 : (itemsByID[pid ?? rootID]?.depth ?? 0) + 1)

		var item = itemsByID[nid] ?? LocationTreeItem(
			id: nid, title: node.title, depth: depth,
			isExpandable: true, isExpanded: expanded.contains(nid), isLoading: false
		)

		// update visuals
		item.title = node.title
		item.isLoading = { if case .loading = node.state { return true } else { return false } }()
		switch node.state {
		case .loaded:
			item.isExpandable = !(kids?.isEmpty ?? false)
		case .failed(_):
			item.isExpandable = true
		default:
			item.isExpandable = true
		}

		// seed real root on first paint (not anchor)
		if visibleIDs.isEmpty, nid == rootID { visibleIDs = [rootID] }

		itemsByID[nid] = item

		// If expanded and we know children:
		if expanded.contains(nid), let k = kids {
			if let _ = visibleIDs.firstIndex(of: nid) {
				spliceChildren(of: nid, parentDepth: depth, childIDs: k)
				for cid in k { observeNode(cid); repository.ensureNode(cid) }
			} else {
				// Parent not visible yet -> queue for later
				pendingChildren[nid] = k
			}
		} else {
			observeNode(nid); repository.ensureNode(nid)
		}

		publish()
	}

	private func spliceChildren(
		of parentID: OCPath,
		parentDepth: Int,
		childIDs: [OCPath]
	) {
		// Refresh parent's area without clearing expansion flags
		removeSubtree(of: parentID, onRemove: nil, clearExpanded: false)

		guard let pIdx = visibleIDs.firstIndex(of: parentID) else {
			// Parent not visible yet — defer
			pendingChildren[parentID] = childIDs
			return
		}

		var newRows: [LocationTreeItem] = []
		newRows.reserveCapacity(childIDs.count)

		for cid in childIDs {
			let snap = repository.currentNode(cid) // may be .idle
			let expandable: Bool = {
				guard let n = snap else { return true }
				if case .loaded = n.state { return !(n.childrenIDs?.isEmpty ?? true) }
				return true
			}()
			newRows.append(
				LocationTreeItem(
					id: cid,
					title: snap?.title ?? titleForPlaceholder(id: cid),
					depth: parentDepth + 1,
					isExpandable: expandable,
					isExpanded: expanded.contains(cid),
					isLoading: false
				)
			)
		}

		visibleIDs.insert(contentsOf: newRows.map(\.id), at: pIdx + 1)
		for r in newRows { itemsByID[r.id] = r }

		// 🔁 Flush grandchildren for children that are already expanded
		for cid in childIDs where expanded.contains(cid) {
			let childDepth = itemsByID[cid]?.depth ?? (parentDepth + 1)

			if let pending = pendingChildren.removeValue(forKey: cid) {
				spliceChildren(of: cid, parentDepth: childDepth, childIDs: pending)
				for gcid in pending { observeNode(gcid); repository.ensureNode(gcid) }
			} else if let snap = repository.currentNode(cid),
					  let grand = snap.childrenIDs {
				// Fallback: use the current snapshot (what the repo already knows)
				spliceChildren(of: cid, parentDepth: childDepth, childIDs: grand)
				for gcid in grand { observeNode(gcid); repository.ensureNode(gcid) }
			}
		}
	}

	private func titleForPlaceholder(id: OCPath) -> String {
		return ""
	}

	@discardableResult
	private func removeSubtree(
		of parentID: OCPath,
		onRemove: ((OCPath) -> Void)?,
		clearExpanded: Bool
	) -> [OCPath] {
		let parentID = Self.norm(parentID)
		guard let parent = itemsByID[parentID],
			  let start  = visibleIDs.firstIndex(of: parentID) else { return [] }

		var removed: [OCPath] = []
		var end = start + 1
		while end < visibleIDs.count {
			let id = visibleIDs[end]
			guard let r = itemsByID[id] else { break }
			if r.depth <= parent.depth { break }
			onRemove?(id)
			if var rr = itemsByID[id] {
				rr.isExpanded = false
				rr.isLoading  = false
				itemsByID[id] = rr
			}
			removed.append(id)
			end += 1
		}
		if end > start + 1 {
			visibleIDs.removeSubrange((start + 1)..<end)
			if clearExpanded { expanded.subtract(removed) }
		}
		return removed
	}

	// Publish flattened items for the VC
	private func publish() {
		items = visibleIDs.compactMap { itemsByID[$0] }
	}
}

// Small helper to compare node status without payloads
private extension LocationTreeNode {
  var statusKey: Int {
	  switch state {
	  case .idle: return 0
	  case .loading: return 1
	  case .loaded: return 2
	  case .failed(_): return 3
	  }
  }
}
