import Foundation
import ownCloudSDK

public enum ZipArchiveError: Int, Error {
	case corruptedArchive = 1
	case insufficientStorage = 2
	case unsupportedEntryNames = 3
	case unexpectedExtraction = 4
	case networkInterrupted = 5
	case encryptedArchive = 6

	public func localizedMessage(for kind: ZipOperationRecord.Kind) -> String {
		switch self {
		case .corruptedArchive:
			return HCL10n.ZipAction.Error.corruptedArchive
		case .insufficientStorage:
			return kind == .decompress
				? HCL10n.ZipAction.Error.insufficientStorage
				: HCL10n.ZipAction.Error.insufficientStorageCompress
		case .unsupportedEntryNames:
			return HCL10n.ZipAction.Error.unsupportedEntryNames
		case .unexpectedExtraction:
			return kind == .decompress
				? HCL10n.ZipAction.Error.unexpectedExtraction
				: HCL10n.ZipAction.Error.unexpectedOperation
		case .networkInterrupted:
			return HCL10n.ZipAction.Error.networkInterrupted
		case .encryptedArchive:
			return HCL10n.ZipAction.Alert.UnsupportedArchive.message
		}
	}

	public var showsRetry: Bool {
		switch self {
		case .insufficientStorage, .networkInterrupted:
			return true
		default:
			return false
		}
	}

	public var presentsAlert: Bool {
		self == .encryptedArchive
	}

	public static func classify(_ error: Error, for kind: ZipOperationRecord.Kind) -> ZipArchiveError {
		if let zipError = error as? ZipArchiveError {
			return zipError
		}

		if isEncryptedArchive(error) {
			return .encryptedArchive
		}
		if isInsufficientStorage(error) {
			return .insufficientStorage
		}
		if isNetworkError(error) {
			return .networkInterrupted
		}

		if kind == .decompress {
			if isUnsupportedNames(error) {
				return .unsupportedEntryNames
			}
			if isCorrupted(error) {
				return .corruptedArchive
			}
			return .unexpectedExtraction
		}

		return .unexpectedExtraction
	}

	private static func isEncryptedArchive(_ error: Error) -> Bool {
		let ns = error as NSError
		return ns.domain == ZipArchiveErrorDomain && ns.code == ZipArchiveError.encryptedArchive.rawValue
	}

	private static func isInsufficientStorage(_ error: Error) -> Bool {
		var current: Error? = error
		var depth = 0
		while let currentError = current, depth < 8 {
			let ns = currentError as NSError
			if ns.domain == NSPOSIXErrorDomain, ns.code == Int(POSIXErrorCode.ENOSPC.rawValue) {
				return true
			}
			if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteOutOfSpaceError {
				return true
			}
			current = ns.userInfo[NSUnderlyingErrorKey] as? Error
			depth += 1
		}
		return false
	}

	private static func isNetworkError(_ error: Error) -> Bool {
		let autoCodes: Set<Int> = [
			URLError.timedOut.rawValue,
			URLError.cannotConnectToHost.rawValue,
			URLError.cannotFindHost.rawValue,
			URLError.dnsLookupFailed.rawValue,
			URLError.networkConnectionLost.rawValue,
			URLError.notConnectedToInternet.rawValue
		]

		var current: Error? = error
		var depth = 0
		while let currentError = current, depth < 8 {
			let ns = currentError as NSError
			if ns.domain == NSURLErrorDomain, autoCodes.contains(ns.code) {
				return true
			}
			if ns.isNetworkFailureError {
				return true
			}
			current = ns.userInfo[NSUnderlyingErrorKey] as? Error
			depth += 1
		}
		return false
	}

	private static func isUnsupportedNames(_ error: Error) -> Bool {
		if let zipError = error as? ZipArchiveError, zipError == .unsupportedEntryNames {
			return true
		}
		let ns = error as NSError
		return ns.domain == ZipArchiveErrorDomain && ns.code == ZipArchiveError.unsupportedEntryNames.rawValue
	}

	private static func isCorrupted(_ error: Error) -> Bool {
		if let zipError = error as? ZipArchiveError, zipError == .corruptedArchive {
			return true
		}

		let ns = error as NSError
		if ns.domain == ZipArchiveErrorDomain, ns.code == ZipArchiveError.corruptedArchive.rawValue {
			return true
		}

		if ns.domain == "ZIPFoundation.Archive.ArchiveError" {
			return true
		}

		var current: Error? = error
		var depth = 0
		while let currentError = current, depth < 8 {
			let inner = currentError as NSError
			if inner.domain == "ZIPFoundation.Archive.ArchiveError" {
				return true
			}
			current = inner.userInfo[NSUnderlyingErrorKey] as? Error
			depth += 1
		}
		return false
	}
}

public let ZipArchiveErrorDomain = "com.owncloud.ziparchive"
