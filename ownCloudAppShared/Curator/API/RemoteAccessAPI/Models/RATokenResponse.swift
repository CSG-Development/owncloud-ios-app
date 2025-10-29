public struct RATokenResponse: Codable {
	public let accessToken: String
	public let refreshToken: String
	public let tokenType: String
	public let expiresIn: Int
}
