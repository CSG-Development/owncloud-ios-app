import Foundation
import ownCloudSDK

public final class ZipOperationRecord: NSObject {
	public enum Kind: String {
		case compress
		case decompress
	}

	public let id: String
	public let kind: Kind
	public let documentName: String
	public let parentLocationKey: String
	public let parentItemLocalID: String?

	public private(set) var statusText: String
	public private(set) var fractionCompleted: Double

	/// Status text shown in the activity UI (respects `ZipOperationProgressStatus.showsDetailedPhaseStatus`).
	public var displayStatusText: String {
		ZipOperationProgressStatus.displayText(for: kind, detailedStatus: statusText)
	}

	public var cancelHandler: (() -> Void)?

	public init(
		id: String = UUID().uuidString,
		kind: Kind,
		documentName: String,
		parentLocationKey: String,
		parentItemLocalID: String? = nil,
		statusText: String = HCL10n.ZipAction.Progress.preparing,
		fractionCompleted: Double = 0
	) {
		self.id = id
		self.kind = kind
		self.documentName = documentName
		self.parentLocationKey = parentLocationKey
		self.parentItemLocalID = parentItemLocalID
		self.statusText = statusText
		self.fractionCompleted = fractionCompleted
		super.init()
	}

	public func update(statusText: String? = nil, fractionCompleted: Double? = nil) {
		if let statusText, !statusText.isEmpty {
			self.statusText = statusText
		}
		if let fractionCompleted {
			self.fractionCompleted = min(1, max(0, fractionCompleted))
		}
	}

	public func cancel() {
		cancelHandler?()
	}

	public static func locationKey(for location: OCLocation?) -> String? {
		guard let location else { return nil }
		let bookmark = location.bookmarkUUID?.uuidString ?? ""
		let drive = location.driveID ?? ""
		var path = location.path ?? "/"
		if path.isEmpty {
			path = "/"
		}
		if !path.hasPrefix("/") {
			path = "/" + path
		}
		if path.count > 1, path.hasSuffix("/") {
			path = String(path.dropLast())
		}
		return "\(bookmark)|\(drive)|\(path)"
	}

	public static func locationKeysLooselyMatch(_ lhs: String, _ rhs: String) -> Bool {
		if lhs == rhs {
			return true
		}

		let leftParts = lhs.split(separator: "|", omittingEmptySubsequences: false)
		let rightParts = rhs.split(separator: "|", omittingEmptySubsequences: false)
		guard leftParts.count == 3, rightParts.count == 3 else {
			return false
		}

		return leftParts[1] == rightParts[1]
			&& leftParts[2] == rightParts[2]
			&& (leftParts[0].isEmpty || rightParts[0].isEmpty || leftParts[0] == rightParts[0])
	}

	public static func locationKey(for item: OCItem) -> String? {
		locationKey(for: item.location)
	}
}

public final class ZipOperationCenter {
	public static let shared = ZipOperationCenter()
	public static let didChangeNotification = Notification.Name("ZipOperationCenterDidChange")

	private let lock = NSLock()
	private var recordsByID: [String: ZipOperationRecord] = [:]
	private var orderedIDs: [String] = []

	private init() {}

	public var operations: [ZipOperationRecord] {
		lock.lock()
		defer { lock.unlock() }
		return orderedIDs.compactMap { recordsByID[$0] }
	}

	public func operations(for location: OCLocation?, parentItemLocalID: String? = nil) -> [ZipOperationRecord] {
		let key = ZipOperationRecord.locationKey(for: location)
		return operations.filter { record in
			if let parentItemLocalID, let recordParentID = record.parentItemLocalID, parentItemLocalID == recordParentID {
				return true
			}
			if let key {
				return ZipOperationRecord.locationKeysLooselyMatch(record.parentLocationKey, key)
			}
			return false
		}
	}

	/// All in-progress operations for a bookmark (shown on every file list in that account).
	public func operations(forBookmarkUUID bookmarkUUID: UUID?) -> [ZipOperationRecord] {
		guard let bookmarkUUID else {
			return operations
		}
		let prefix = bookmarkUUID.uuidString + "|"
		return operations.filter { record in
			record.parentLocationKey.hasPrefix(prefix)
				|| record.parentLocationKey.hasPrefix("|") // legacy / unset bookmark UUID
		}
	}

	public func add(_ record: ZipOperationRecord) {
		lock.lock()
		recordsByID[record.id] = record
		if !orderedIDs.contains(record.id) {
			orderedIDs.append(record.id)
		}
		lock.unlock()
		notifyChanged()
	}

	public func update(_ record: ZipOperationRecord, statusText: String? = nil, fractionCompleted: Double? = nil) {
		record.update(statusText: statusText, fractionCompleted: fractionCompleted)
		notifyChanged()
	}

	public func remove(id: String) {
		lock.lock()
		recordsByID.removeValue(forKey: id)
		orderedIDs.removeAll { $0 == id }
		lock.unlock()
		notifyChanged()
	}

	private func notifyChanged() {
		OnMainThread {
			NotificationCenter.default.post(name: ZipOperationCenter.didChangeNotification, object: self)
		}
	}
}
