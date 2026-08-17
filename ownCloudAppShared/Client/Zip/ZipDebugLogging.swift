import Foundation
import ownCloudSDK

public enum ZipDebugLogging {
	public static let tag = ["Zip"]

	/// Per-entry / per-file zip tracing and PROFILE timings. Off by default —
	/// a 1000-file extract otherwise floods the log.
	public static var isVerbose = false

	public static func log(_ message: String) {
		guard isVerbose else { return }
		Log.debug(tagged: tag, "%@", message)
	}

	/// Timing scope for decompress/compress bottlenecks. Emits only when `isVerbose`.
	public final class ProfileScope {
		public let name: String
		private let start: CFAbsoluteTime
		private var lastMark: CFAbsoluteTime

		public init(_ name: String, extra: String = "") {
			self.name = name
			self.start = CFAbsoluteTimeGetCurrent()
			self.lastMark = start
			guard ZipDebugLogging.isVerbose else { return }
			let suffix = extra.isEmpty ? "" : " \(extra)"
			Log.debug(tagged: ZipDebugLogging.tag, "%@", "⏱ PROFILE begin \(name)\(suffix)")
		}

		/// Elapsed since scope start (and optionally since previous mark).
		@discardableResult
		public func mark(_ label: String, extra: String = "") -> TimeInterval {
			let now = CFAbsoluteTimeGetCurrent()
			let sinceStartMs = (now - start) * 1000
			let sinceMarkMs = (now - lastMark) * 1000
			lastMark = now
			if ZipDebugLogging.isVerbose {
				let suffix = extra.isEmpty ? "" : " \(extra)"
				Log.debug(
					tagged: ZipDebugLogging.tag,
					"%@",
					"⏱ PROFILE mark \(name).\(label) +\(Self.formatMs(sinceMarkMs)) (total \(Self.formatMs(sinceStartMs)))\(suffix)"
				)
			}
			return now - start
		}

		@discardableResult
		public func end(extra: String = "") -> TimeInterval {
			let elapsed = CFAbsoluteTimeGetCurrent() - start
			if ZipDebugLogging.isVerbose {
				let suffix = extra.isEmpty ? "" : " \(extra)"
				Log.debug(tagged: ZipDebugLogging.tag, "%@", "⏱ PROFILE end \(name) elapsed=\(Self.formatMs(elapsed * 1000))\(suffix)")
			}
			return elapsed
		}

		private static func formatMs(_ ms: Double) -> String {
			if ms >= 1000 {
				return String(format: "%.2fs", ms / 1000)
			}
			return String(format: "%.0fms", ms)
		}
	}

	public static func log(error: Error, context: String) {
		let nsError = error as NSError
		Log.debug(
			tagged: tag,
			"%@",
			"\(context): error domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)"
		)
	}

	public static func log(item: OCItem, context: String) {
		guard isVerbose else { return }
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
		guard isVerbose else { return }
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
		guard isVerbose else { return }
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
