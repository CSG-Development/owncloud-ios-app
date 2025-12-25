import Foundation

public extension RemoteDevice.Path.Kind {
	var priority: Int {
		switch self {
		case .local:  return 0
		case .public: return 1
		case .remote: return 2
		}
	}
}

extension RemoteDevice.Path.Kind: Comparable {
	public static func < (lhs: Self, rhs: Self) -> Bool { lhs.priority < rhs.priority }
}

public extension RemoteDevice.Path {
	/// Stable identifier for dictionaries/caches
	var key: String {
		let kindString: String = {
			switch kind {
			case .remote: return "remote"
			case .public: return "public"
			case .local:  return "local"
			}
		}()
		return "\(kindString)|\(address)|\(port ?? -1)"
	}

	func apiBaseURL(defaultScheme: String = "https", basePath: String = "api/v1") -> URL? {
		URL(host: address, port: port, path: basePath)
	}
}

public extension Array where Element == RemoteDevice.Path {
	/// Ordered by kind priority, then case-insensitive address:port
	func ordered() -> [Element] {
		sorted { a, b in
			if a.kind != b.kind { return a.kind < b.kind }
			let aa = "\(a.address):\(a.port ?? -1)"
			let bb = "\(b.address):\(b.port ?? -1)"
			return aa.localizedCaseInsensitiveCompare(bb) == .orderedAscending
		}
	}
}

extension URL {
	public init?(host: String, port: Int? = nil, path: String? = nil) {
		var resultStr = host

		if resultStr.hasSuffix("/") {
			resultStr = String(resultStr.dropLast())
		}

		if let port {
			resultStr = "\(resultStr):\(port)/"
		} else {
			resultStr = "\(resultStr)/"
		}

		if var path {
			if path.hasPrefix("/") {
				path = String(path.dropFirst())
			}
			if path.hasSuffix("/") {
				path = String(path.dropLast())
			}
			resultStr = "\(resultStr)\(path)"
		}

		let hasScheme = resultStr.hasPrefix("http://") || resultStr.hasPrefix("https://")
		if !hasScheme {
			resultStr = "https://\(resultStr)"
		}
		self.init(string: resultStr)
	}
}
