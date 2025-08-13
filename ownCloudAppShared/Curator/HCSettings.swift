import ownCloudSDK

private enum UserDefaultsKeys {
	static let shouldShowOnboarding = "shouldShowOnboarding"
}

public final class HCSettings {
	public static let shared = HCSettings()

	public var shouldShowOnboarding: Bool {
		get {
			guard let userDefaults = OCAppIdentity.shared.userDefaults else {
				return false
			}
			return userDefaults.bool(forKey: UserDefaultsKeys.shouldShowOnboarding)
		}
		set {
			guard let userDefaults = OCAppIdentity.shared.userDefaults else { return }
			userDefaults.set(newValue, forKey: UserDefaultsKeys.shouldShowOnboarding)
		}
	}
}
