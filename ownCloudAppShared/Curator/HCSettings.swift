import ownCloudSDK

private enum UserDefaultsKeys {
	static let shouldShowOnboarding = "shouldShowOnboarding"
    static let onboardingSeenPageIndices = "onboardingSeenPageIndices"
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

    public var onboardingSeenPageIndices: Set<Int> {
        get {
            guard let userDefaults = OCAppIdentity.shared.userDefaults else {
                return []
            }
            if let array = userDefaults.array(forKey: UserDefaultsKeys.onboardingSeenPageIndices) as? [Int] {
                return Set(array)
            }
            return []
        }
        set {
            guard let userDefaults = OCAppIdentity.shared.userDefaults else { return }
            userDefaults.set(Array(newValue), forKey: UserDefaultsKeys.onboardingSeenPageIndices)
        }
    }
}
