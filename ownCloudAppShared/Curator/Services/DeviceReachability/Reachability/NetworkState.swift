import Network

public struct NetworkState: Equatable, Sendable {
	public enum Interface: String, Sendable {
		case wifi, cellular, wired, other, none
	}

	public let status: NWPath.Status
	public let isReachable: Bool
	public let isExpensive: Bool
	public let interface: Interface

	public init(
		status: NWPath.Status,
		isReachable: Bool,
		isExpensive: Bool,
		interface: Interface
	) {
		self.status = status
		self.isReachable = isReachable
		self.isExpensive = isExpensive
		self.interface = interface
	}
}
