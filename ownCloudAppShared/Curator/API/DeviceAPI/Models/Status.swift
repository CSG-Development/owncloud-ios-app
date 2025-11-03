public struct Status: Codable, Sendable {
	public struct OOBE: Codable, Sendable {
		public let done: Bool
	}
	public enum State: String, Codable, Sendable {
		case ready
		case busy
		case error
		case unknown
	}
	public let state: State
	public let OOBE: OOBE
}
