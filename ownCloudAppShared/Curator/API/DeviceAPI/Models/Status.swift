public struct Status: Codable, Sendable {
	public struct OOBE: Codable, Sendable {
		public var done: Bool
	}
	public struct Apps: Codable, Sendable {
		public struct AppStatus: Codable, Sendable {
			public var isReady: Bool

			public init(from decoder: Decoder) throws {
				let container = try decoder.singleValueContainer()

				// Accept bools or strings like "ready"
				if let boolValue = try? container.decode(Bool.self) {
					self.isReady = boolValue
					return
				}

				if let stringValue = try? container.decode(String.self) {
					self.isReady = stringValue.lowercased() == "ready"
					return
				}

				self.isReady = false
			}

			public init(isReady: Bool) {
				self.isReady = isReady
			}
		}
		public var files: AppStatus?
		public var photos: AppStatus?
	}
	public enum State: String, Codable, Sendable {
		case ready
		case busy
		case error
		case unknown
	}
	public var state: State
	public var OOBE: OOBE
	public var apps: Apps?
}
