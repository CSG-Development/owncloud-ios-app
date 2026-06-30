//
//  OCItem+TrashPresentation.swift
//  ownCloud
//
//  Copyright © 2025 ownCloud GmbH. All rights reserved.
//

import UniformTypeIdentifiers
import ownCloudSDK

extension OCItem {
	var isTrashItem: Bool {
		value(forLocalAttribute: OCLocalAttribute.trashItem) != nil
	}

	var isPendingTrashItem: Bool {
		value(forLocalAttribute: OCLocalAttribute.trashPendingSyncRecordID) != nil
	}

	static func isUninformativeMIMEType(_ mimeType: String?) -> Bool {
		guard let mimeType, !mimeType.isEmpty else { return true }
		return mimeType == "application/octet-stream" || mimeType == "binary/octet-stream"
	}

	var trashEffectiveMimeType: String? {
		if let mimeType, !Self.isUninformativeMIMEType(mimeType) {
			return mimeType
		}
		if let originalFilename = value(forLocalAttribute: OCLocalAttribute.trashOriginalFilename) as? String,
		   let mimeType = Self.mimeType(forFilename: originalFilename) {
			return mimeType
		}
		if let originalLocation = value(forLocalAttribute: OCLocalAttribute.trashOriginalLocation) as? String,
		   let mimeType = Self.mimeType(forFilename: originalLocation) {
			return mimeType
		}
		return nil
	}

	@discardableResult
	func trashApplyPresentationMimeType() -> OCItem {
		guard let effectiveMimeType = trashEffectiveMimeType else { return self }
		if Self.isUninformativeMIMEType(mimeType) {
			mimeType = effectiveMimeType
		}
		return self
	}

	var previewMIMEType: String? {
		trashApplyPresentationMimeType()
		if let mimeType, !mimeType.isEmpty {
			return mimeType
		}
		return trashEffectiveMimeType
	}

	static func mimeType(forFilename filename: String) -> String? {
		let pathExtension = (filename as NSString).pathExtension
		guard !pathExtension.isEmpty else { return nil }
		return UTType(filenameExtension: pathExtension)?.preferredMIMEType
	}
}
