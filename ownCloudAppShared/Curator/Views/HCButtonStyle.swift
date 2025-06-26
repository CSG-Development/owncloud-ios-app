public enum HCButtonStyle {
	public enum Configuration {
		case plain
		case outlined
		case filled
	}

	case primary(configuration: Configuration)
	case secondary(configuration: Configuration)

	public var isOutlined: Bool {
		switch self {
			case let .primary(configuration: configuration):
				return configuration == .outlined
			case let .secondary(configuration: configuration):
				return configuration == .outlined
		}
	}
}
