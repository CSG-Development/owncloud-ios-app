//
//  CutPasteboardState.swift
//  ownCloudAppShared
//
//  Tracks items placed on the internal cut pasteboard so the file list can
//  mark them visually until they are pasted or the clipboard is cleared.
//

import Foundation
import ownCloudSDK

public final class CutPasteboardState {
	public static let shared = CutPasteboardState()
	public static let didChangeNotification = Notification.Name("CutPasteboardStateDidChange")

	public private(set) var cutLocalIDs: Set<OCLocalID> = []
	public private(set) var bookmarkUUID: String?

	private init() {}

	public func setCut(items: [OCItem], bookmarkUUID: String) {
		cutLocalIDs = Set(items.compactMap { $0.localID as OCLocalID? })
		self.bookmarkUUID = bookmarkUUID
		notify()
	}

	public func clear() {
		guard !cutLocalIDs.isEmpty || bookmarkUUID != nil else { return }
		cutLocalIDs = []
		bookmarkUUID = nil
		notify()
	}

	public func contains(_ item: OCItem) -> Bool {
		guard let localID = item.localID as OCLocalID? else { return false }
		return cutLocalIDs.contains(localID)
	}

	private func notify() {
		NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
	}
}
