public struct About: Codable, Sendable {
	public var hostname: String
	public var certificate_common_name: String
	public var os_state: String?
}
