import Foundation
import ownCloudSDK

public struct RemoteAccessToken: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    public let accessTokenExpiry: Date?
    public let refreshTokenExpiry: Date?

    public init(
		accessToken: String,
		refreshToken: String,
		tokenType: String,
		accessTokenExpiry: Date?,
		refreshTokenExpiry: Date?
	) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.accessTokenExpiry = accessTokenExpiry
        self.refreshTokenExpiry = refreshTokenExpiry
    }

	init(raTokenResponse: RATokenResponse) {
		self.accessToken = raTokenResponse.accessToken
		self.refreshToken = raTokenResponse.refreshToken
		self.tokenType = raTokenResponse.tokenType
		self.accessTokenExpiry = Date().addingTimeInterval(TimeInterval(raTokenResponse.expiresIn))
		self.refreshTokenExpiry = nil
	}
}

public final class RemoteAccessTokenStore {
    private let keychainAccount = "curator.remoteAccess.tokens"
    private let keyPath = "favoriteDeviceTokens"
    private let queue = DispatchQueue(label: "RemoteAccessTokenStore.queue")

    private var keychain: OCKeychain? {
		// TODO: Update for keychain sharing.
        return OCAppIdentity.shared.keychain
    }

    @discardableResult
    public func save(_ tokens: RemoteAccessToken?) -> Bool {
        return queue.sync {
            return saveInternal(tokens)
        }
    }

    public func loadTokens() -> RemoteAccessToken? {
        return queue.sync {
            loadInternal()
        }
    }

    @discardableResult
    public func clear() -> Bool {
        return queue.sync {
			keychain?.removeItem(forAccount: keychainAccount, path: keyPath) == nil
        }
    }
    
    private func loadInternal() -> RemoteAccessToken? {
        guard let data = keychain?.readDataFromKeychainItem(forAccount: keychainAccount, path: keyPath) else { return nil }
        return (try? JSONDecoder.iso8601.decode(RemoteAccessToken.self, from: data))
    }

    @discardableResult
    private func saveInternal(_ tokens: RemoteAccessToken?) -> Bool {
        guard let data = try? JSONEncoder.iso8601.encode(tokens) else { return false }
        return keychain?.write(data, toKeychainItemForAccount: keychainAccount, path: keyPath) == nil
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
