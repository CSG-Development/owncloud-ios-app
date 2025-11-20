import Foundation
import ownCloudSDK
import Foundation

private enum UserDefaultsKeys {
	static let keyShouldShowOnboarding = "shouldShowOnboarding"
	static let keyOnboardingSeenPageIndices = "onboardingSeenPageIndices"
	static let keyCurrentCN = "currentCertificateCN"
	static let keyCurrentEmail = "currentEmail"
	static let keyCurrentDevice = "currentConnectedDevice"
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

	public var currentEmail: String? {
		get {
			queue.sync {
				userDefaults.string(forKey: UserDefaultsKeys.keyCurrentEmail)
			}
		}
		set {
			queue.async {
				if let newValue {
					self.userDefaults.set(newValue, forKey: UserDefaultsKeys.keyCurrentEmail)
				} else {
					self.userDefaults.removeObject(forKey: UserDefaultsKeys.keyCurrentEmail)
				}
			}
		}
	}

	public var currentCertificateCN: String? {
		get {
			queue.sync {
				userDefaults.string(forKey: UserDefaultsKeys.keyCurrentCN)
			}
		}
		set {
			queue.async {
				if let newValue {
					self.userDefaults.set(newValue, forKey: UserDefaultsKeys.keyCurrentCN)
				} else {
					self.userDefaults.removeObject(forKey: UserDefaultsKeys.keyCurrentCN)
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
}
