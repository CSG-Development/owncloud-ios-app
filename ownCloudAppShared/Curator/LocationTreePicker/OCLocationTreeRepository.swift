import Combine
import ownCloudSDK

public final class OCLocationTreeRepository: LocationTreeRepository {
	private let q = DispatchQueue(label: "live.tree.repo", qos: .userInitiated)
	private let qKey = DispatchSpecificKey<UInt8>()

	private var subjects: [OCPath: CurrentValueSubject<LocationTreeNode, Never>] = [:]
	private var childSinks: [OCPath: AnyCancellable] = [:]     // one sink per parent
	private var refCount: [OCPath: Int] = [:]                   // observeNode subscribers

	// Optional: keep best-known titles (so we can emit child node snapshots)
	private var titles: [OCPath: String] = [:]
	private var parentMap: [OCPath: OCPath?] = [:]

	private let core: OCCore
	private var streams: [OCPath: SharedOCItemsStream] = [:]
	private let streamsLock = NSLock()
	private var lastChildIDs: [OCPath: [OCPath]] = [:]

	@inline(__always)
	private static func norm(_ p: OCPath) -> OCPath {
		var s = ((p as String) as NSString).standardizingPath
		if s.isEmpty { s = "/" }
		if s != "/" && !s.hasSuffix("/") { s += "/" }
		return (s as NSString) as OCPath
	}

	init(core: OCCore) {
		self.core = core
		q.setSpecific(key: qKey, value: 1)
	}

	func currentNode(_ id: OCPath) -> LocationTreeNode? {
		qSync {
			if let s = subjects[id] { return s.value }
			if let title = titles[id] {
				return LocationTreeNode(
					id: id,
					parentID: parentMap[id] ?? nil,
					title: title,
					state: .idle,
					childrenIDs: nil
				)
			}
			return nil
		}
	}

	func parentForNode(_ path: OCPath) -> OCPath? {
		guard path != "/" else { return nil }
		
		let location = OCLocation(driveID: nil, path: path as String)
		return location.parent?.path as OCPath?
	}

	func titleForItem(_ item: OCItem) -> String {
		item.name ?? ""
	}

	func idForItem(_ item: OCItem) -> OCPath {
		(item.location?.path ?? "") as OCPath
	}

	@inline(__always)
	private func qSync<T>(_ body: () -> T) -> T {
		dispatchPrecondition(condition: .notOnQueue(q))
		// If we're already on `q`, run inline; otherwise use `q.sync`
		if DispatchQueue.getSpecific(key: qKey) != nil { return body() }
		return q.sync(execute: body)
	}

	func childrenStream(for path: OCPath) -> AnyPublisher<[OCItem], Never> {
		streamsLock.lock()
		let stream: SharedOCItemsStream
		if let existing = streams[path] {
			stream = existing
		} else {
			stream = SharedOCItemsStream(core: core, path: path, onEmpty: { [weak self] emptyPath in
				guard let self = self else { return }
				self.streamsLock.lock()
				self.streams.removeValue(forKey: emptyPath)
				self.streamsLock.unlock()
			})
			streams[path] = stream
		}
		streamsLock.unlock()

		return stream.publisher()
	}

	func observeNode(_ id: OCPath) -> AnyPublisher<LocationTreeNode, Never> {
		let subject: CurrentValueSubject<LocationTreeNode, Never> = qSync({ () -> CurrentValueSubject<LocationTreeNode, Never> in
				if let s = subjects[id] { return s }
				let title = titles[id] ?? "Item"
				let new = CurrentValueSubject<LocationTreeNode, Never>(
					LocationTreeNode(
						id: id,
						parentID: parentForNode(id),
						title: title,
						state: .idle,
						childrenIDs: nil
					)
				)
				subjects[id] = new
				return new
			}
		)

		// Ref-count this node; start/stop backend sink tied to overall observation
		return subject
			.handleEvents(
				receiveSubscription: { [weak self] _ in self?.q.async { self?.incRef(id) } },
				receiveCancel:       { [weak self] in  self?.q.async { self?.decRef(id) } }
			)
			.eraseToAnyPublisher()
	}

	// MARK: ensureNode

	func ensureNode(_ id: OCPath) {
		q.async {
			guard let s = self.subjects[id] else {
				// create subject lazily then mark loading
				let title = self.titles[id] ?? ""
				let s2 = CurrentValueSubject<LocationTreeNode, Never>(LocationTreeNode(
					id: id,
					parentID: self.parentForNode(id),
					title: title,
					state: .idle,
					childrenIDs: nil
				))
				self.subjects[id] = s2
				self.markLoading(id, subject: s2)
				self.attachChildrenStream(for: id, to: s2)
				return
			}
			// If already attached to children stream, no-op
			if self.childSinks[id] != nil { return }
			self.markLoading(id, subject: s)
			self.attachChildrenStream(for: id, to: s)
		}
	}

	// MARK: warm chain (optional; just kicks loads)

	func warmChainToRoot(from anchorID: OCPath) {
		q.async {
			var cur: OCPath? = anchorID
			while let id = cur {
				// ensure subject exists
				if self.subjects[id] == nil {
					let title = self.titles[id] ?? "Files"
					self.subjects[id] = CurrentValueSubject(LocationTreeNode(
						id: id,
						parentID: self.parentForNode(id),
						title: title,
						state: .idle,
						childrenIDs: nil
					))
				}
				self.ensureNode(id)
				cur = self.parentForNode(id)
			}
		}
	}

	// ---- Helpers on q ----

	private func incRef(_ id: OCPath) {
		refCount[id, default: 0] += 1
		// (Optional) autoload when first UI subscriber appears:
		// if refCount[id] == 1 { ensureNode(id) }
	}

	private func decRef(_ id: OCPath) {
		guard let n = refCount[id] else { return }
		let m = n - 1
		if m <= 0 {
			refCount[id] = nil
			// Cancel backend sink for this parent (stops childrenItemsPublisher)
			childSinks[id]?.cancel()
			childSinks[id] = nil
			// You may also choose to drop the subject after some TTL.
		} else {
			refCount[id] = m
		}
	}

	private func markLoading(_ id: OCPath, subject s: CurrentValueSubject<LocationTreeNode, Never>) {
		let snap = s.value
		guard case .loaded = snap.state else {
			s.send(LocationTreeNode(
				id: snap.id,
				parentID: snap.parentID,
				title: snap.title,
				state: .loading,
				childrenIDs: snap.childrenIDs
			))
			return
		}
	}

	private func attachChildrenStream(
		for rawParent: OCPath,
		to subject: CurrentValueSubject<LocationTreeNode, Never>
	) {
		let parentID = Self.norm(rawParent)
		guard childSinks[parentID] == nil else { return }

		childSinks[parentID] = childrenStream(for: parentID)
			// If you can, filter early to folders only:
			// .map { $0.filter(self.isFolder) }
			.map { items -> ([OCPath], [(id: OCPath, title: String)]) in
				var ids: [OCPath] = []
				ids.reserveCapacity(items.count)
				var pairs: [(OCPath, String)] = []
				for it in items {
					let cid = Self.norm(self.idForItem(it))
					ids.append(cid)
					pairs.append((cid, self.titleForItem(it)))
				}
				return (ids, pairs)
			}
			// Drop duplicates at publisher level to avoid churn
			.removeDuplicates(by: { $0.0 == $1.0 })
			.receive(on: q)
			.sink { [weak self] payload in
				guard let self = self else { return }
				let (ids, pairs) = payload

				// If identical to last sent, ignore
				if self.lastChildIDs[parentID] == ids { return }
				self.lastChildIDs[parentID] = ids

				// Seed/update child subjects (ALWAYS send a child snapshot)
				for (cid, title) in pairs {
					self.titles[cid] = title
					let prev = self.subjects[cid]?.value
					let snap = LocationTreeNode(
						id: cid,
						parentID: parentID,
						title: title,
						state: prev?.state ?? .idle,
						childrenIDs: prev?.childrenIDs
					)
					if let s = self.subjects[cid] {
						s.send(snap)
					} else {
						self.subjects[cid] = CurrentValueSubject(snap)
					}
				}

				let prevParent = subject.value
				subject.send(
					LocationTreeNode(
						id: prevParent.id,
						parentID: prevParent.parentID,
						title: prevParent.title,
						state: .loaded,
						childrenIDs: ids
					)
				)
			}
	}
}
