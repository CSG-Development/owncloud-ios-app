import Foundation
import ownCloudSDK

private enum UserDefaultsKeys {
	static let keyShouldShowOnboarding = "shouldShowOnboarding"
	static let keyOnboardingSeenPageIndices = "onboardingSeenPageIndices"

	static let keyFavoriteDeviceCN = "favoriteDeviceCN"
	static let keyFavoriteEmail = "favoriteEmail"

	static let keyCurrentDevice = "currentConnectedDevice"

	static let keyTrustedDeviceCerts = "trustedDeviceCerts"
}

@objcMembers
public final class HCPreferences: NSObject {
	public static let shared = HCPreferences()

	private let queue = DispatchQueue(label: "com.curator.preferences")
	private let userDefaults = OCAppIdentity.shared.userDefaults ?? UserDefaults.standard

	public override init() { super.init() }

	public var shouldShowOnboarding: Bool {
		get {
			queue.sync {
				userDefaults.bool(forKey: UserDefaultsKeys.keyShouldShowOnboarding)
			}
		}
		set {
			queue.async {
				self.userDefaults.set(newValue, forKey: UserDefaultsKeys.keyShouldShowOnboarding)
			}
		}
	}

	public var onboardingSeenPageIndices: Set<Int> {
		get {
			queue.sync {
				if let array = userDefaults.array(forKey: UserDefaultsKeys.keyOnboardingSeenPageIndices) as? [Int] {
					return Set(array)
				}
				return Set()
			}
		}
		set {
			queue.async {
				self.userDefaults.set(Array(newValue), forKey: UserDefaultsKeys.keyOnboardingSeenPageIndices)
			}
		}
	}

	public var favoriteEmail: String? {
		get {
			queue.sync {
				userDefaults.string(forKey: UserDefaultsKeys.keyFavoriteEmail)
			}
		}
		set {
			queue.async {
				if let newValue {
					self.userDefaults.set(newValue, forKey: UserDefaultsKeys.keyFavoriteEmail)
				} else {
					self.userDefaults.removeObject(forKey: UserDefaultsKeys.keyFavoriteEmail)
				}
			}
		}
	}

	public var favoriteDeviceCN: String? {
		get {
			queue.sync {
				userDefaults.string(forKey: UserDefaultsKeys.keyFavoriteDeviceCN)
			}
		}
		set {
			queue.async {
				if let newValue {
					self.userDefaults.set(newValue, forKey: UserDefaultsKeys.keyFavoriteDeviceCN)
				} else {
					self.userDefaults.removeObject(forKey: UserDefaultsKeys.keyFavoriteDeviceCN)
				}
			}
		}
	}

	// MARK: - Connected device (persist full device to probe after relaunch)
	public struct SavedConnectedDevice: Codable {
		public struct SavedPath: Codable {
			public enum Kind: String, Codable { case local, `public`, remote }
			public let kind: Kind
			public let address: String
			public let port: Int?
			public init(kind: Kind, address: String, port: Int?) {
				self.kind = kind
				self.address = address
				self.port = port
			}
		}
		public let seagateDeviceID: String?
		public let certificateCommonName: String
		public let friendlyName: String?
		public let hostname: String?
		public let paths: [SavedPath]

		public init(seagateDeviceID: String? = nil, certificateCommonName: String, friendlyName: String?, hostname: String?, paths: [SavedPath]) {
			self.seagateDeviceID = seagateDeviceID
			self.certificateCommonName = certificateCommonName
			self.friendlyName = friendlyName
			self.hostname = hostname
			self.paths = paths
		}
	}

	public var currentConnectedDevice: SavedConnectedDevice? {
		get {
			queue.sync {
				guard let data = userDefaults.data(forKey: UserDefaultsKeys.keyCurrentDevice) else { return nil }
				return try? JSONDecoder().decode(SavedConnectedDevice.self, from: data)
			}
		}
		set {
			queue.async {
				if let newValue, let data = try? JSONEncoder().encode(newValue) {
					self.userDefaults.set(data, forKey: UserDefaultsKeys.keyCurrentDevice)
				} else {
					self.userDefaults.removeObject(forKey: UserDefaultsKeys.keyCurrentDevice)
				}
			}
		}
	}

	// MARK: - Trusted device/ownCloud certificates (user-accepted)
	public var trustedDeviceCertificates: [Data] {
		get {
			queue.sync {
				(userDefaults.array(forKey: UserDefaultsKeys.keyTrustedDeviceCerts) as? [Data]) ?? []
			}
		}
		set {
			queue.async {
				self.userDefaults.set(newValue, forKey: UserDefaultsKeys.keyTrustedDeviceCerts)
			}
		}
	}

	public func addTrustedDeviceCertificate(_ der: Data) {
		queue.async {
			var current = (self.userDefaults.array(forKey: UserDefaultsKeys.keyTrustedDeviceCerts) as? [Data]) ?? []
			if current.contains(der) == false {
				current.append(der)
				self.userDefaults.set(current, forKey: UserDefaultsKeys.keyTrustedDeviceCerts)
			}
		}
	}
}
