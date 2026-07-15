import Foundation

struct ProxyResource: Sendable {
	let remoteURL: URL
	let headers: [String: String]
	let createdAt: Date
}
