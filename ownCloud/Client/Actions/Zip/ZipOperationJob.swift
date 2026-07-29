import Foundation
import ownCloudSDK
import ownCloudAppShared

enum ZipOperationPhase: String, Codable {
	case preparing
	case downloading
	case archiving
	case importing
	case failed
	case completed

	/// Maps persisted values, including legacy `"uploading"`.
	static func fromPersisted(_ raw: String) -> ZipOperationPhase? {
		if raw == "uploading" {
			return .importing
		}
		return ZipOperationPhase(rawValue: raw)
	}
}

/// Durable zip compress/decompress job that can survive app relaunch.
final class ZipOperationJob: NSObject, NSSecureCoding {
	enum Kind: String {
		case compress
		case decompress
	}

	static let maxAutoRetryAttempts = 3

	let id: String
	let kind: Kind
	let bookmarkUUID: UUID
	var documentName: String
	var parentLocationKey: String
	var parentItemLocalID: String?
	var sourceItemLocalIDs: [String]
	var zipItemLocalID: String?
	/// Items that already had a local copy when the job started (logging / diagnostics).
	var alreadyLocalItemLocalIDs: [String]
	/// Legacy: vault locals downloaded for older job paths (ignored by new temp-download pipeline).
	var downloadedForJobLocalIDs: [String]
	/// Relative paths already copied/downloaded into `downloads/` (resume skip list).
	var materializedRelativePaths: [String]
	/// Folders created during decompress import (delete deepest-first on cancel).
	var createdFolderLocalIDs: [String]
	/// Files imported during compress/decompress (delete on cancel).
	var uploadedFileLocalIDs: [String]
	/// Relative paths already imported into the vault (resume skip list).
	var uploadedRelativePaths: [String]
	var phase: ZipOperationPhase
	var statusText: String
	var fractionCompleted: Double
	var workingDirectoryName: String
	var archiveFileName: String?
	var suggestedUploadName: String?
	var uploadPlaceholderLocalID: String?
	var lastErrorDescription: String?
	var attemptCount: Int
	var updatedAt: Date

	static var supportsSecureCoding: Bool { true }

	init(
		id: String = UUID().uuidString,
		kind: Kind,
		bookmarkUUID: UUID,
		documentName: String,
		parentLocationKey: String,
		parentItemLocalID: String?,
		sourceItemLocalIDs: [String] = [],
		zipItemLocalID: String? = nil,
		alreadyLocalItemLocalIDs: [String] = [],
		downloadedForJobLocalIDs: [String] = [],
		materializedRelativePaths: [String] = [],
		createdFolderLocalIDs: [String] = [],
		uploadedFileLocalIDs: [String] = [],
		uploadedRelativePaths: [String] = [],
		phase: ZipOperationPhase = .preparing,
		statusText: String = HCL10n.ZipAction.Progress.preparing,
		fractionCompleted: Double = 0,
		workingDirectoryName: String = UUID().uuidString,
		archiveFileName: String? = nil,
		suggestedUploadName: String? = nil,
		uploadPlaceholderLocalID: String? = nil,
		lastErrorDescription: String? = nil,
		attemptCount: Int = 0,
		updatedAt: Date = Date()
	) {
		self.id = id
		self.kind = kind
		self.bookmarkUUID = bookmarkUUID
		self.documentName = documentName
		self.parentLocationKey = parentLocationKey
		self.parentItemLocalID = parentItemLocalID
		self.sourceItemLocalIDs = sourceItemLocalIDs
		self.zipItemLocalID = zipItemLocalID
		self.alreadyLocalItemLocalIDs = alreadyLocalItemLocalIDs
		self.downloadedForJobLocalIDs = downloadedForJobLocalIDs
		self.materializedRelativePaths = materializedRelativePaths
		self.createdFolderLocalIDs = createdFolderLocalIDs
		self.uploadedFileLocalIDs = uploadedFileLocalIDs
		self.uploadedRelativePaths = uploadedRelativePaths
		self.phase = phase
		self.statusText = statusText
		self.fractionCompleted = fractionCompleted
		self.workingDirectoryName = workingDirectoryName
		self.archiveFileName = archiveFileName
		self.suggestedUploadName = suggestedUploadName
		self.uploadPlaceholderLocalID = uploadPlaceholderLocalID
		self.lastErrorDescription = lastErrorDescription
		self.attemptCount = attemptCount
		self.updatedAt = updatedAt
		super.init()
	}

	func encode(with coder: NSCoder) {
		coder.encode(id, forKey: "id")
		coder.encode(kind.rawValue, forKey: "kind")
		coder.encode(bookmarkUUID, forKey: "bookmarkUUID")
		coder.encode(documentName, forKey: "documentName")
		coder.encode(parentLocationKey, forKey: "parentLocationKey")
		coder.encode(parentItemLocalID, forKey: "parentItemLocalID")
		coder.encode(sourceItemLocalIDs, forKey: "sourceItemLocalIDs")
		coder.encode(zipItemLocalID, forKey: "zipItemLocalID")
		coder.encode(alreadyLocalItemLocalIDs, forKey: "alreadyLocalItemLocalIDs")
		coder.encode(downloadedForJobLocalIDs, forKey: "downloadedForJobLocalIDs")
		coder.encode(materializedRelativePaths, forKey: "materializedRelativePaths")
		coder.encode(createdFolderLocalIDs, forKey: "createdFolderLocalIDs")
		coder.encode(uploadedFileLocalIDs, forKey: "uploadedFileLocalIDs")
		coder.encode(uploadedRelativePaths, forKey: "uploadedRelativePaths")
		coder.encode(phase.rawValue, forKey: "phase")
		coder.encode(statusText, forKey: "statusText")
		coder.encode(NSNumber(value: fractionCompleted), forKey: "fractionCompleted")
		coder.encode(workingDirectoryName, forKey: "workingDirectoryName")
		coder.encode(archiveFileName, forKey: "archiveFileName")
		coder.encode(suggestedUploadName, forKey: "suggestedUploadName")
		coder.encode(uploadPlaceholderLocalID, forKey: "uploadPlaceholderLocalID")
		coder.encode(lastErrorDescription, forKey: "lastErrorDescription")
		coder.encode(NSNumber(value: attemptCount), forKey: "attemptCount")
		coder.encode(updatedAt, forKey: "updatedAt")
	}

	required init?(coder: NSCoder) {
		guard let id = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
		      let kindRaw = coder.decodeObject(of: NSString.self, forKey: "kind") as String?,
		      let kind = Kind(rawValue: kindRaw),
		      let bookmarkUUID = coder.decodeObject(of: NSUUID.self, forKey: "bookmarkUUID") as UUID?,
		      let documentName = coder.decodeObject(of: NSString.self, forKey: "documentName") as String?,
		      let parentLocationKey = coder.decodeObject(of: NSString.self, forKey: "parentLocationKey") as String?,
		      let phaseRaw = coder.decodeObject(of: NSString.self, forKey: "phase") as String?,
		      let phase = ZipOperationPhase.fromPersisted(phaseRaw),
		      let statusText = coder.decodeObject(of: NSString.self, forKey: "statusText") as String?,
		      let workingDirectoryName = coder.decodeObject(of: NSString.self, forKey: "workingDirectoryName") as String? else {
			return nil
		}

		self.id = id
		self.kind = kind
		self.bookmarkUUID = bookmarkUUID
		self.documentName = documentName
		self.parentLocationKey = parentLocationKey
		self.parentItemLocalID = coder.decodeObject(of: NSString.self, forKey: "parentItemLocalID") as String?
		self.sourceItemLocalIDs = (coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "sourceItemLocalIDs") as? [String]) ?? []
		self.zipItemLocalID = coder.decodeObject(of: NSString.self, forKey: "zipItemLocalID") as String?
		self.alreadyLocalItemLocalIDs = (coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "alreadyLocalItemLocalIDs") as? [String]) ?? []
		self.downloadedForJobLocalIDs = (coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "downloadedForJobLocalIDs") as? [String]) ?? []
		self.materializedRelativePaths = (coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "materializedRelativePaths") as? [String]) ?? []
		self.createdFolderLocalIDs = (coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "createdFolderLocalIDs") as? [String]) ?? []
		self.uploadedFileLocalIDs = (coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "uploadedFileLocalIDs") as? [String]) ?? []
		self.uploadedRelativePaths = (coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "uploadedRelativePaths") as? [String]) ?? []
		self.phase = phase
		self.statusText = statusText
		self.fractionCompleted = (coder.decodeObject(of: NSNumber.self, forKey: "fractionCompleted") as NSNumber?)?.doubleValue ?? 0
		self.workingDirectoryName = workingDirectoryName
		self.archiveFileName = coder.decodeObject(of: NSString.self, forKey: "archiveFileName") as String?
		self.suggestedUploadName = coder.decodeObject(of: NSString.self, forKey: "suggestedUploadName") as String?
		self.uploadPlaceholderLocalID = coder.decodeObject(of: NSString.self, forKey: "uploadPlaceholderLocalID") as String?
		self.lastErrorDescription = coder.decodeObject(of: NSString.self, forKey: "lastErrorDescription") as String?
		self.attemptCount = (coder.decodeObject(of: NSNumber.self, forKey: "attemptCount") as NSNumber?)?.intValue ?? 0
		self.updatedAt = coder.decodeObject(of: NSDate.self, forKey: "updatedAt") as Date? ?? Date()
		super.init()
	}

	func touch() {
		updatedAt = Date()
	}

	var canAutoRetry: Bool {
		attemptCount < Self.maxAutoRetryAttempts
	}

	var workingDirectoryURL: URL {
		Self.rootDirectory.appendingPathComponent(workingDirectoryName, isDirectory: true)
	}

	var archiveURL: URL? {
		guard let archiveFileName else { return nil }
		return workingDirectoryURL.appendingPathComponent(archiveFileName, isDirectory: false)
	}

	var extractDirectoryURL: URL {
		workingDirectoryURL.appendingPathComponent("extract", isDirectory: true)
	}

	var downloadsDirectoryURL: URL {
		workingDirectoryURL.appendingPathComponent("downloads", isDirectory: true)
	}

	func ensureWorkingDirectory() throws {
		try FileManager.default.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true, attributes: [
			.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
		])
		try FileManager.default.createDirectory(at: downloadsDirectoryURL, withIntermediateDirectories: true, attributes: [
			.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
		])
	}

	func removeWorkingDirectory() {
		try? FileManager.default.removeItem(at: workingDirectoryURL)
	}

	static var rootDirectory: URL {
		let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
		let root = base.appendingPathComponent("ZipOperations", isDirectory: true)
		try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}
}

final class ZipOperationJobStore: NSObject, NSSecureCoding {
	static let storageKey = OCKeyValueStoreKey(rawValue: "com.owncloud.zip-operation-jobs")
	var jobsByID: [String: ZipOperationJob] = [:]

	static var supportsSecureCoding: Bool { true }

	override init() {
		super.init()
	}

	func encode(with coder: NSCoder) {
		coder.encode(jobsByID, forKey: "jobsByID")
	}

	required init?(coder: NSCoder) {
		jobsByID = (coder.decodeObject(of: [NSDictionary.self, NSString.self, ZipOperationJob.self], forKey: "jobsByID") as? [String: ZipOperationJob]) ?? [:]
		super.init()
	}

	var incompleteJobs: [ZipOperationJob] {
		jobsByID.values
			.filter { $0.phase != .completed }
			.sorted { $0.updatedAt < $1.updatedAt }
	}

	/// Jobs that should be auto-resumed. Failed jobs stay out of the activity queue until the user taps Retry.
	var resumableJobs: [ZipOperationJob] {
		incompleteJobs.filter { $0.phase != .failed }
	}
}

extension OCKeyValueStore {
	func registerZipOperationClasses() {
		if registeredClasses(forKey: ZipOperationJobStore.storageKey) == nil {
			if let classSet = NSSet(array: [
				ZipOperationJobStore.self,
				ZipOperationJob.self,
				NSDictionary.self,
				NSArray.self,
				NSString.self,
				NSNumber.self,
				NSDate.self,
				NSUUID.self
			]) as? Set<AnyHashable> {
				registerClasses(classSet, forKey: ZipOperationJobStore.storageKey)
			}
		}
	}
}

extension OCBookmark {
	private static var zipKVSCache: [UUID: OCKeyValueStore] = [:]

	var zipOperationKeyValueStore: OCKeyValueStore? {
		var keyValueStore: OCKeyValueStore?
		OCSynchronized(OCBookmark.self) {
			if let cached = OCBookmark.zipKVSCache[self.uuid] {
				keyValueStore = cached
			} else {
				let vault = OCVault(bookmark: self)
				if let rootURL = vault.rootURL {
					let store = OCKeyValueStore(
						url: rootURL.appendingPathComponent("zipOperations.db", isDirectory: false),
						identifier: "\(self.uuid.uuidString).zipOperations"
					)
					store.registerZipOperationClasses()
					OCBookmark.zipKVSCache[self.uuid] = store
					keyValueStore = store
				}
			}
		}
		return keyValueStore
	}

	func modifyZipOperationStore(with modifier: @escaping (ZipOperationJobStore) -> ZipOperationJobStore) {
		zipOperationKeyValueStore?.updateObject(forKey: ZipOperationJobStore.storageKey, usingModifier: { value, changesMadePtr in
			var store = value as? ZipOperationJobStore ?? ZipOperationJobStore()
			store = modifier(store)
			changesMadePtr.pointee = true
			return store
		})
	}

	var zipOperationStore: ZipOperationJobStore {
		(zipOperationKeyValueStore?.readObject(forKey: ZipOperationJobStore.storageKey) as? ZipOperationJobStore) ?? ZipOperationJobStore()
	}

	func saveZipJob(_ job: ZipOperationJob) {
		job.touch()
		modifyZipOperationStore { store in
			store.jobsByID[job.id] = job
			return store
		}
	}

	func removeZipJob(id: String) {
		modifyZipOperationStore { store in
			if let job = store.jobsByID.removeValue(forKey: id) {
				job.removeWorkingDirectory()
			}
			return store
		}
	}
}
