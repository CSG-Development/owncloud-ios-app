public struct Status: Codable {
	public struct OOBE: Codable {
		public let done: Bool
	}
	public enum State: String, Codable {
		case ready
		case busy
		case error
		case unknown
	}
	public let state: State
	public let OOBE: OOBE
}
