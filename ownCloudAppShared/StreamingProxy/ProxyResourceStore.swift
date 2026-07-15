import Foundation

final class ProxyResourceStore {
	static let defaultExpirationInterval: TimeInterval = 30 * 60

	private let lock = NSLock()
	private var resourcesByID: [UUID: ProxyResource] = [:]
	private let expirationInterval: TimeInterval

	init(expirationInterval: TimeInterval = ProxyResourceStore.defaultExpirationInterval) {
		self.expirationInterval = expirationInterval
	}

	func register(remoteURL: URL, headers: [String: String], proxyBaseURL: URL) -> URL {
		let id = UUID()
		let proxyURL = proxyBaseURL
			.appendingPathComponent("proxy")
			.appendingPathComponent(id.uuidString)

		lock.withLock {
			resourcesByID[id] = ProxyResource(remoteURL: remoteURL, headers: headers, createdAt: Date())
		}
		return proxyURL
	}

	func resolve(id: UUID) -> ProxyResource? {
		lock.withLock {
			guard let resource = resourcesByID[id] else { return nil }
			if resource.createdAt < cutoff {
				resourcesByID.removeValue(forKey: id)
				return nil
			}
			return resource
		}
	}

	func remove(proxyURL: URL) {
		guard let id = UUID(uuidString: proxyURL.lastPathComponent) else { return }
		lock.withLock { resourcesByID.removeValue(forKey: id) }
	}

	func removeExpiredResources() {
		lock.withLock {
			resourcesByID = resourcesByID.filter { $0.value.createdAt > cutoff }
		}
	}

	private var cutoff: Date { Date(timeIntervalSinceNow: -expirationInterval) }
}
