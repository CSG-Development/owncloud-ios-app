import Foundation

enum ProxyHTTPMessage {
	// RFC 7230 §6.1 hop-by-hop headers that must not be forwarded
	private static let hopByHopResponseHeaders: Set<String> = [
		"connection", "keep-alive", "transfer-encoding", "upgrade",
		"content-encoding", "proxy-authenticate", "proxy-connection",
		"trailer", "te"
	]

	static func filteredResponseHeaders(from httpResponse: HTTPURLResponse) -> [String: String] {
		var headers: [String: String] = [:]
		for (rawName, rawValue) in httpResponse.allHeaderFields {
			guard let name = rawName as? String, let value = rawValue as? String else { continue }
			if !hopByHopResponseHeaders.contains(name.lowercased()) {
				headers[name] = value
			}
		}
		return headers
	}

	static func responseBodyByteCount(from httpResponse: HTTPURLResponse) -> Int? {
		if let value = httpResponse.value(forHTTPHeaderField: "Content-Length"),
		   let count = Int(value), count >= 0 {
			return count
		}

		if let value = httpResponse.value(forHTTPHeaderField: "Content-Range"),
		   let count = byteCount(fromContentRange: value) {
			return count
		}

		let length = httpResponse.expectedContentLength
		return length > 0 ? Int(length) : nil
	}

	static func byteCount(fromContentRange value: String) -> Int? {
		// Format: "bytes <start>-<end>/<total>" or "bytes */<total>" or "bytes <start>-<end>/*"
		let trimmed = value.trimmingCharacters(in: .whitespaces)
		guard trimmed.lowercased().hasPrefix("bytes ") else { return nil }

		let rest = String(trimmed.dropFirst(6))
		let parts = rest.split(separator: "/", maxSplits: 1)
		guard parts.count == 2 else { return nil }

		let rangePart = String(parts[0])
		guard rangePart != "*" else { return nil }  // unknown range

		let bounds = rangePart.split(separator: "-", omittingEmptySubsequences: false)
		guard bounds.count == 2,
			  let start = Int(bounds[0]),
			  let end = Int(bounds[1]),
			  end >= start else { return nil }
		return end - start + 1
	}

	static func byteCount(fromRangeHeader value: String) -> Int? {
		// Format: "bytes=<start>-<end>"
		let trimmed = value.trimmingCharacters(in: .whitespaces)
		guard trimmed.lowercased().hasPrefix("bytes=") else { return nil }

		let rangePart = String(trimmed.dropFirst(6))
		let bounds = rangePart.split(separator: "-", omittingEmptySubsequences: false)
		guard bounds.count == 2,
			  let start = Int(bounds[0]),
			  let end = Int(bounds[1]),
			  end >= start else { return nil }
		return end - start + 1
	}
}
