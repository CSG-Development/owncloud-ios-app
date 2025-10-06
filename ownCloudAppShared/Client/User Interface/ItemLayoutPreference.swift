import ownCloudSDK

public enum ItemLayoutPreference {
	private static let userDefaultsKey = "preferred-item-layout"

	public static var preferred: ItemLayout {
		get { load() }
		set { save(newValue) }
	}

	public static func load() -> ItemLayout {
		guard let userDefaults = OCAppIdentity.shared.userDefaults else {
			return .list
		}

		if let stored = userDefaults.string(forKey: userDefaultsKey), let layout = layout(from: stored) {
			return layout
		}

		return .list
	}

	public static func save(_ layout: ItemLayout) {
		guard let userDefaults = OCAppIdentity.shared.userDefaults else { return }
		userDefaults.set(string(from: layout), forKey: userDefaultsKey)
	}

	private static func string(from layout: ItemLayout) -> String {
		switch layout {
			case .list: return "list"
			case .grid: return "grid"
			case .gridLowDetail: return "gridLowDetail"
			case .gridNoDetail: return "gridNoDetail"
		}
	}

	private static func layout(from string: String) -> ItemLayout? {
		switch string {
			case "list": return .list
			case "grid": return .grid
			case "gridLowDetail": return .gridLowDetail
			case "gridNoDetail": return .gridNoDetail
			default: return nil
		}
	}
}
