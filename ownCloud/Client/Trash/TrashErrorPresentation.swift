//
//  TrashErrorPresentation.swift
//  ownCloud
//
//  Copyright © 2025 ownCloud GmbH. All rights reserved.
//

import Foundation
import ownCloudSDK
import ownCloudAppShared

enum TrashErrorPresentation {
	static var nameConflictNSError: NSError {
		NSError(
			domain: OCErrorDomain,
			code: Int(OCError.itemAlreadyExists.rawValue),
			userInfo: [NSLocalizedDescriptionKey: HCL10n.Trash.Restore.nameConflict]
		)
	}

	static func userMessage(for error: Error) -> String {
		let nsError = error as NSError

		if nsError.isOCError(withCode: .itemAlreadyExists) {
			return HCL10n.Trash.Restore.nameConflict
		}

		if isNameConflictError(error) {
			return HCL10n.Trash.Restore.nameConflict
		}

		return error.localizedDescription
	}

	static func isNameConflictError(_ error: Error) -> Bool {
		let nsError = error as NSError

		if nsError.isOCError(withCode: .itemAlreadyExists) {
			return true
		}

		if let davName = nsError.davExceptionName,
		   davName.contains("FileLocked")
			|| davName.contains("PreconditionFailed")
			|| davName.contains("Conflict") {
			return true
		}

		let combined = [nsError.localizedDescription, nsError.davExceptionMessage]
			.compactMap { $0?.lowercased() }
			.joined(separator: " ")

		if combined.contains("already exists") || combined.contains(" is locked") {
			return true
		}

		return false
	}

	static func isTransientLockError(_ error: Error) -> Bool {
		let nsError = error as NSError

		if let davName = nsError.davExceptionName, davName.contains("FileLocked") {
			return true
		}

		let message = (nsError.davExceptionMessage ?? nsError.localizedDescription).lowercased()
		return message.contains("locked")
	}
}
