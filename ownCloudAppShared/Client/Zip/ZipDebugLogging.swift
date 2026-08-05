import Foundation
import ownCloudSDK

public enum ZipDebugLogging {
	public static let tag = ["Zip"]

	public static func log(_ message: String) {
		Log.debug(tagged: tag, "%@", message)
	}

	public static func log(error: Error, context: String) {
		let nsError = error as NSError
		log("\(context): error domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
	}

	public static func log(item: OCItem, context: String) {
		log("""
		\(context): \
		name=\(Log.mask(item.name ?? "nil")) \
		path=\(Log.mask(item.path ?? "nil")) \
		type=\(item.type.rawValue) \
		mimeType=\(item.mimeType ?? "nil") \
		fileID=\(item.fileID ?? "nil") \
		localID=\(item.localID ?? "nil") \
		size=\(item.size) \
		syncActivity=\(item.syncActivity.rawValue)
		""")
	}

	public static func log(items: [OCItem], context: String) {
		log("\(context): \(items.count) item(s)")
		for (index, item) in items.enumerated() {
			log(item: item, context: "\(context)[\(index)]")
		}
	}

	/// Human-readable byte count: "1.45 GB", "234 KB", "512 B".
	public static func formattedBytes(_ bytes: Int64) -> String {
		let units: [(Double, String)] = [(1_073_741_824, "GB"), (1_048_576, "MB"), (1_024, "KB")]
		for (factor, label) in units where bytes >= Int64(factor) {
			return String(format: "%.2f %@", Double(bytes) / factor, label)
		}
		return "\(bytes) B"
	}

	public static func log(url: URL, context: String) {
		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
		var fileSize: Int64?

		if exists && !isDirectory.boolValue {
			fileSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
		}

		log("""
		\(context): \
		path=\(Log.mask(url.path)) \
		exists=\(exists) \
		isDirectory=\(isDirectory.boolValue) \
		fileSize=\(fileSize.map(String.init) ?? "nil")
		""")
	}
}
