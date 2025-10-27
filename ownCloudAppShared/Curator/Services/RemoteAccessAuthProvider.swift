import Foundation

final class RemoteAccessAuthProvider: AuthProvider {
    private let email: String
    private var currentAccessTokenInternal: String?
    private var currentRefreshTokenInternal: String?

    init(email: String) {
        self.email = email
        // Load latest token for email, if any
        if let last = RemoteAccessTokenStore.shared.loadTokens(for: email).last {
            currentAccessTokenInternal = last.accessToken
            currentRefreshTokenInternal = last.refreshToken
        }
    }

    // MARK: - AuthProvider
    var accessToken: String? { currentAccessTokenInternal }

    func isRefreshRequest(_ request: URLRequest?) -> Bool {
        guard let url = request?.url else { return false }
        return url.absoluteString.contains("/client/v1/auth/refresh")
    }

    func refreshAccessToken() async throws -> String {
        guard let refresh = currentRefreshTokenInternal, !refresh.isEmpty else {
            throw NSError(domain: "RemoteAccessAuthProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing refresh token"])
        }
        let sema = AsyncSemaphore<String>()
        RemoteAccessService.shared.refreshAccessToken(refreshToken: refresh) { result in
            switch result {
                case .success(let response):
                    let newToken = RemoteAccessToken(
                        accessToken: response.accessToken,
                        refreshToken: response.refreshToken,
                        tokenType: response.tokenType,
                        accessTokenExpiry: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
                        refreshTokenExpiry: nil
                    )
                    _ = RemoteAccessTokenStore.shared.save(tokens: newToken, for: self.email)
                    self.currentAccessTokenInternal = newToken.accessToken
                    self.currentRefreshTokenInternal = newToken.refreshToken
                    sema.resume(with: .success(newToken.accessToken))
                case .failure(let error):
                    sema.resume(with: .failure(error))
            }
        }
        return try await sema.value()
    }

    func logout() {
        _ = RemoteAccessTokenStore.shared.clear(email: email)
        currentAccessTokenInternal = nil
        currentRefreshTokenInternal = nil
    }
}

// Simple helper to bridge callback to async
private final class AsyncSemaphore<T> {
    private var cont: CheckedContinuation<T, Error>?

    func resume(with result: Result<T, Error>) {
        guard let cont else { return }
        switch result {
            case .success(let value): cont.resume(returning: value)
            case .failure(let error): cont.resume(throwing: error)
        }
    }

    func value() async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            self.cont = cont
        }
    }
}


