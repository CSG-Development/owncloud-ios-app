//
//  OCItem+LocalTagSnapshots.swift
//  ownCloudAppShared
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

import Foundation
import ownCloudSDK
import ownCloudApp

public extension OCItem {
	public struct LocalTagSnapshot: Hashable {
		let id: String?
		let name: String
	}

	private static let localTagSchemaVersion = 2

	public func setLocalTagSnapshots(_ snapshots: [LocalTagSnapshot], refreshedAt: Date = Date()) {
		let payloadTags = snapshots.map { snapshot in
			var tagDictionary: [String: Any] = ["name": snapshot.name]
			if let id = snapshot.id {
				tagDictionary["id"] = id
			}
			return tagDictionary
		}

		let legacyRows: [[Any]] = snapshots.map { snapshot in
			[snapshot.name, NSNumber(value: 0)]
		}

		let payload: [String: Any] = [
			"v": NSNumber(value: Self.localTagSchemaVersion),
			"tags": payloadTags,
			"t": legacyRows
		]

		if let archivedData = try? NSKeyedArchiver.archivedData(withRootObject: payload, requiringSecureCoding: false) {
			setValue(archivedData, forLocalAttribute: OCLocalAttribute.tagData)
		}
	}

	public func setLocalTagSnapshots(from systemTags: [OCSystemTag], refreshedAt: Date = Date()) {
		let visibleTags = systemTags.filter(\.userVisible)
		let snapshots = visibleTags.map { LocalTagSnapshot(id: $0.identifier, name: $0.displayName) }
		setLocalTagSnapshots(snapshots, refreshedAt: refreshedAt)
	}
}
