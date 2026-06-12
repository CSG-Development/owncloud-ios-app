import Foundation

public enum ResetPasswordURLNormalizer {
	public static func normalizeServerBaseURL(_ url: URL) -> URL {
		if url.path.hasSuffix("/files") {
			return url.deletingLastPathComponent()
		}
		return url
	}
}

public struct ResetPasswordService: Sendable {
	public init() {}

	public func resetPassword(serverBaseURL: URL, email: String) async throws {
		guard !email.isEmpty else {
			throw ResetPasswordError.validationFailed
		}

		let normalizedURL = ResetPasswordURLNormalizer.normalizeServerBaseURL(serverBaseURL)
		guard !normalizedURL.absoluteString.isEmpty else {
			throw ResetPasswordError.validationFailed
		}

		let api = DeviceAPI(deviceBaseURL: normalizedURL, requestTimeout: 60)
		try await api.resetPassword(email: email)
	}
}
