public enum RADevicePathKind: String, Codable {
	case local
	case `public`
	case remote
}

public struct RADevicePath: Codable {
	public let type: RADevicePathKind
	public let address: String
	public let port: Int?
}
