public enum HCButtonStyle {
	public enum Configuration {
		case plain
		case outlined
		case filled
	}

	case primary(configuration: Configuration)
	case secondary(configuration: Configuration)

	public var configuration: Configuration {
		switch self {
			case let .primary(configuration: configuration),
			     let .secondary(configuration: configuration):
				return configuration
		}
	}

	public var isOutlined: Bool {
		configuration == .outlined
	}
}
