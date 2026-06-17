import Network

public struct NetworkState: Equatable, Sendable {
	public enum Interface: String, Sendable {
		case wifi, cellular, wired, other, none

		public var allowsLocalPaths: Bool {
			switch self {
				case .cellular: return false
				case .wifi, .wired, .other, .none: return true
			}
		}
	}

	public let status: NWPath.Status
	public let isReachable: Bool
	public let isExpensive: Bool
	public let interface: Interface

	/// Local / mDNS paths are allowed on any non-cellular interface.
	public var allowsLocalPaths: Bool {
		interface.allowsLocalPaths
	}

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
