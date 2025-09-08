import Combine
import ownCloudSDK

final class SharedOCItemsStream {
	typealias Output = [OCItem]
	typealias Failure = Never

	private let core: OCCore
	private let path: OCPath
	private let callbackQueue: DispatchQueue
	private let trackDifferences: Bool
	private let performInitialUpdate: Bool

	private let subject = PassthroughSubject<[OCItem], Never>()
	private var query: OCQuery?
	private var handle: OCDataSourceSubscription?
	private var subscriberCount = 0
	private let lock = NSLock() // simple serialization

	private var onEmpty: ((OCPath) -> Void)?

	init(
		core: OCCore,
		path: OCPath,
		callbackQueue: DispatchQueue = .main,
		trackDifferences: Bool = false,
		performInitialUpdate: Bool = true,
		onEmpty: ((OCPath) -> Void)?
	) {
		self.core = core
		self.path = path
		self.callbackQueue = callbackQueue
		self.trackDifferences = trackDifferences
		self.performInitialUpdate = performInitialUpdate
		self.onEmpty = onEmpty
	}

	deinit {
		stopQueryIfNeeded()
	}

	func publisher() -> AnyPublisher<[OCItem], Never> {
		subject
			.handleEvents(
				receiveSubscription: { [weak self] _ in self?.increment() },
				receiveCancel:       { [weak self] in self?.decrement() }
			)
			.eraseToAnyPublisher()
	}

	private func increment() {
		lock.lock(); defer { lock.unlock() }
		subscriberCount += 1
		if subscriberCount == 1 { startQueryIfNeeded() }
	}

	private func decrement() {
		lock.lock(); defer { lock.unlock() }
		subscriberCount = max(0, subscriberCount - 1)
		if subscriberCount == 0 {
			stopQueryIfNeeded()
			onEmpty?(path)
		}
	}

	private func startQueryIfNeeded() {
		guard handle == nil else { return }
		let location = OCLocation(driveID: nil, path: path as String)
		location.bookmarkUUID = core.bookmark.uuid
		let q = OCQuery(for: location)
		q.sortComparator = { left, right in
			guard let li = left as? OCItem, let ri = right as? OCItem else { return .orderedSame }
			if li.type == .collection && ri.type != .collection { return .orderedAscending }
			if li.type != .collection && ri.type == .collection { return .orderedDescending }
			if let ln = li.name, let rn = ri.name { return ln.caseInsensitiveCompare(rn) }
			return .orderedSame
		}
		query = q
		core.start(q)
		handle = q.queryResultsDataSource?.subscribe(
			updateHandler: { [weak self] sub in
				guard let self = self else { return }
				let snapshot = sub.snapshotResettingChangeTracking(true)
				var items: [OCItem] = []
				for ref in snapshot.items {
					if let record = try? sub.source?.record(forItemRef: ref),
					   record.type == .item,
					   let item = record.item as? OCItem {
						items.append(item)
					}
				}
				items = items.filter { $0.type == .collection }
				self.subject.send(items)
			},
			on: callbackQueue,
			trackDifferences: trackDifferences,
			performInitialUpdate: performInitialUpdate
		)
	}

	private func stopQueryIfNeeded() {
		handle?.terminate()
		if let q = query { core.stop(q) }
		handle = nil
		query = nil
	}
}
