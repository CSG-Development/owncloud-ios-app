public enum RADevicePathKind: String, Codable {
	case local
	case `public`
	case remote
}

public struct RADevicePath: Codable {
	public var type: RADevicePathKind
	public var address: String
	public var port: Int?
}
