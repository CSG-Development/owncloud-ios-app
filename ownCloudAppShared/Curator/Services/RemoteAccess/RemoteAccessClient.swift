import Foundation

actor RemoteAccessClient {
	private let api: RemoteAccessAPI
	private let tokenStore: RemoteAccessTokenStore

	private var inFlightTokenUpdate: Task<String, Error>?

	init(api: RemoteAccessAPI, tokenStore: RemoteAccessTokenStore) {
		self.api = api
		self.tokenStore = tokenStore
	}

	func sendEmailCode(email: String, clientId: String, clientFriendlyName: String) async throws -> RAInitiateResponse {
		try await api.sendEmailCode(email: email, clientId: clientId, clientFriendlyName: clientFriendlyName)
	}

	func validateEmailCode(code: String, clientId: String, reference: String) async throws {
		let token = try await performTokenUpdate {
			try await self.api.validateEmailCode(code: code, clientId: clientId, reference: reference)
		}
		api.accessToken = token
	}

	func listDevices(clientId: String) async throws -> [RADevice] {
		try await authedCall(clientId: clientId) {
			try await api.listDevices()
		}
	}

	func getDevicePaths(clientId: String, deviceID: String) async throws -> RADevicePaths {
		try await authedCall(clientId: clientId) {
			try await api.getDevicePaths(deviceID: deviceID)
		}
	}

	private func authedCall<T>(
		clientId: String,
		_ body: @Sendable () async throws -> T
	) async throws -> T {
		if let t = inFlightTokenUpdate {
			let token = try await t.value
			api.accessToken = token
			return try await body()
		}

		let token = try await ensureValidAccessToken(clientId: clientId)
		api.accessToken = token

		do {
			return try await body()
		} catch let ns as NSError where ns.domain == "RemoteAccessAPI" && ns.code == 401 {
			let newToken = try await forceRefresh(clientId: clientId)
			api.accessToken = newToken
			return try await body()
		}
	}

	private func ensureValidAccessToken(clientId: String) async throws -> String {
		if let t = inFlightTokenUpdate {
			return try await t.value
		}

		guard let tokens = tokenStore.loadTokens(),
			  !tokens.refreshToken.isEmpty
		else {
			_ = tokenStore.clear()
			throw RemoteAccessServiceError.unauthorized
		}

		if let exp = tokens.accessTokenExpiry, Date() <= exp {
			return tokens.accessToken
		}

		return try await performTokenUpdate {
			try await self.api.refreshAccessToken(clientId: clientId, refreshToken: tokens.refreshToken)
		}
	}

	private func forceRefresh(clientId: String) async throws -> String {
		if let t = inFlightTokenUpdate { return try await t.value }

		guard let tokens = tokenStore.loadTokens(),
			  !tokens.refreshToken.isEmpty
		else {
			_ = tokenStore.clear()
			throw RemoteAccessServiceError.unauthorized
		}

		return try await performTokenUpdate {
			try await self.api.refreshAccessToken(clientId: clientId, refreshToken: tokens.refreshToken)
		}
	}

	private func performTokenUpdate(
		_ op: @escaping @Sendable () async throws -> RATokenResponse
	) async throws -> String {
		if let t = inFlightTokenUpdate {
			return try await t.value
		}

		let task = Task<String, Error> { [weak self] in
			guard let self else { throw CancellationError() }
			return try await self.runTokenUpdate(op)
		}

		inFlightTokenUpdate = task
		defer { inFlightTokenUpdate = nil }

		return try await task.value
	}

	private func runTokenUpdate(
		_ op: @Sendable () async throws -> RATokenResponse
	) async throws -> String {
		do {
			let resp = try await op()

			let tokens = RemoteAccessToken(raTokenResponse: resp)
			_ = tokenStore.save(tokens)

			guard let updated = tokenStore.loadTokens() else {
				_ = tokenStore.clear()
				throw RemoteAccessServiceError.unauthorized
			}

			api.accessToken = updated.accessToken
			return updated.accessToken
		} catch {
			if let ns = error as NSError?,
			   ns.domain == "RemoteAccessAPI",
			   (400...499).contains(ns.code) {
				_ = tokenStore.clear()
				throw RemoteAccessServiceError.unauthorized
			}
			throw error
		}
	}

	func hasValidTokens(clientId: String) async -> Bool {
		do {
			_ = try await ensureValidAccessToken(clientId: clientId)
			return true
		} catch let e as RemoteAccessServiceError where e == .unauthorized {
			return false
		} catch let ns as NSError where ns.domain == "RemoteAccessAPI" && (400...499).contains(ns.code) {
			_ = tokenStore.clear()
			return false
		} catch is URLError {
			return true
		} catch {
			return true
		}
	}

	func clearTokens() {
		if let t = inFlightTokenUpdate {
			t.cancel()
			inFlightTokenUpdate = nil
		}

		_ = tokenStore.clear()
		api.accessToken = nil
	}
}
