import Foundation
import UIKit

/// Tracks in-flight zip operations for the current bookmark and drives the activity section cell.
final class FileListZipActivityController {
	private(set) var operations: [ZipOperationRecord] = []
	private(set) var isExpanded = false

	/// Fired when `ZipOperationCenter` posts a change. Host should call `reload` handling.
	var onExternalChange: (() -> Void)?
	/// Fired after a user expands/collapses the activity card.
	var onExpansionChanged: (() -> Void)?

	private var observer: NSObjectProtocol?
	private var bookmarkUUIDProvider: (() -> UUID?)?

	var hasOperations: Bool {
		!operations.isEmpty
	}

	var activityItemIDs: [String] {
		operations.isEmpty ? [] : [FileListItemID.activity]
	}

	func startObserving(bookmarkUUIDProvider: @escaping () -> UUID?) {
		self.bookmarkUUIDProvider = bookmarkUUIDProvider
		guard observer == nil else { return }
		observer = NotificationCenter.default.addObserver(
			forName: ZipOperationCenter.didChangeNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.onExternalChange?()
		}
	}

	func stopObserving() {
		if let observer {
			NotificationCenter.default.removeObserver(observer)
			self.observer = nil
		}
	}

	/// Reloads operations for the current bookmark. Returns whether membership (IDs) changed.
	@discardableResult
	func reload() -> Bool {
		let bookmarkUUID = bookmarkUUIDProvider?()
		let previousIDs = Set(operations.map(\.id))
		operations = ZipOperationCenter.shared.operations(forBookmarkUUID: bookmarkUUID)
		let nextIDs = Set(operations.map(\.id))
		let membershipChanged = previousIDs != nextIDs
		if operations.isEmpty || operations.count == 1 {
			isExpanded = false
		}
		return membershipChanged
	}

	@discardableResult
	func toggleExpanded() -> Bool {
		guard operations.count > 1 else { return false }
		isExpanded.toggle()
		return true
	}

	func configure(_ cell: FileListZipOperationCell, animatedExpansion: Bool = false) {
		cell.configure(records: operations, expanded: isExpanded, animated: animatedExpansion)
		cell.onToggleExpanded = { [weak self] in
			guard let self, self.toggleExpanded() else { return }
			self.onExpansionChanged?()
		}
		cell.onCancelRecord = { record in
			record.cancel()
		}
	}

	func preferredHeight() -> CGFloat {
		FileListZipOperationCell.preferredHeight(expanded: isExpanded, operationCount: operations.count)
	}

	deinit {
		stopObserving()
	}
}
