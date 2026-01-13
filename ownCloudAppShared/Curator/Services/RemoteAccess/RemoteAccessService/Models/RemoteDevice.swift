public struct RemoteDevice: Sendable, Codable {
	public let seagateDeviceID: String
	public let friendlyName: String
	public let hostname: String
	public let certificateCommonName: String
	public let paths: [Path]

	public struct Path: Sendable, Codable {
		public enum Kind: String, Sendable, Codable {
			case local
			case `public`
			case remote

			init(raDevicePathKind: RADevicePathKind) {
				self = switch raDevicePathKind {
					case .local: .local
					case .`public`: .`public`
					case .remote: .remote
				}
			}
		}

		public let kind: Kind
		public let address: String
		public let port: Int?

		init(raDevicePath: RADevicePath) {
			self.kind = Kind(raDevicePathKind: raDevicePath.type)
			self.address = raDevicePath.address
			self.port = raDevicePath.port
		}
	}

	public init(
		seagateDeviceID: String,
		friendlyName: String,
		hostname: String,
		certificateCommonName: String,
		paths: [Path]
	) {
		self.seagateDeviceID = seagateDeviceID
		self.friendlyName = friendlyName
		self.hostname = hostname
		self.certificateCommonName = certificateCommonName
		self.paths = paths
	}

	init(
		raDevice: RADevice,
		raDevicePaths: RADevicePaths
	) {
		self.init(
			seagateDeviceID: raDevice.seagateDeviceID,
			friendlyName: raDevice.friendlyName,
			hostname: raDevice.hostname,
			certificateCommonName: raDevice.certificateCommonName,
			paths: raDevicePaths.paths.map { Path(raDevicePath: $0) }
		)
	}
}
