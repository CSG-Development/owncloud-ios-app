import Foundation

public struct TokenBundle: Codable {
	public let accessToken: String?
	public let accessTokenExpiry: Date?
	public let refreshToken: String?
	public let refreshTokenExpiry: Date?
}

public final class TokenSecureStorage {
	private let keychainAccount = "curator.tokens"
	private let keyPath: String
	private let queue = DispatchQueue(label: "TokenSecureStorage.queue")

	private var keychain: OCKeychain? {
		return OCAppIdentity.shared.keychain
	}

	public init(namespace: String = "default") {
		self.keyPath = "bundle." + namespace
	}

	// MARK: - Save / Load
	@discardableResult
	public func saveTokens(accessToken: String?, accessExpiry: Date?, refreshToken: String?, refreshExpiry: Date?) -> Bool {
		let bundle = TokenBundle(accessToken: accessToken, accessTokenExpiry: accessExpiry, refreshToken: refreshToken, refreshTokenExpiry: refreshExpiry)
		return save(bundle: bundle)
	}

	@discardableResult
	public func save(bundle: TokenBundle) -> Bool {
		return queue.sync {
			guard let data = try? JSONEncoder.iso8601.encode(bundle) else { return false }
			return keychain?.write(data, toKeychainItemForAccount: keychainAccount, path: keyPath) == nil
		}
	}

	public func load() -> TokenBundle? {
		return queue.sync {
			guard let data = keychain?.readDataFromKeychainItem(forAccount: keychainAccount, path: keyPath) else { return nil }
			return try? JSONDecoder.iso8601.decode(TokenBundle.self, from: data)
		}
	}

	@discardableResult
	public func clear() -> Bool {
		return queue.sync {
			return keychain?.removeItem(forAccount: keychainAccount, path: keyPath) == nil
		}
	}

	// MARK: - Convenience
	public var accessToken: String? { load()?.accessToken }
	public var refreshToken: String? { load()?.refreshToken }

	public func isAccessTokenExpired(referenceDate: Date = Date()) -> Bool {
		guard let exp = load()?.accessTokenExpiry else { return true }
		return exp <= referenceDate
	}

	public func isRefreshTokenExpired(referenceDate: Date = Date()) -> Bool {
		guard let exp = load()?.refreshTokenExpiry else { return true }
		return exp <= referenceDate
	}
}

private extension JSONEncoder {
	static var iso8601: JSONEncoder {
		let enc = JSONEncoder()
		enc.dateEncodingStrategy = .iso8601
		return enc
	}
}

private extension JSONDecoder {
	static var iso8601: JSONDecoder {
		let dec = JSONDecoder()
		dec.dateDecodingStrategy = .iso8601
		return dec
	}
}
