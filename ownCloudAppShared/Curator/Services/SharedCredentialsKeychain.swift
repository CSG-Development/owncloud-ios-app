import Foundation
import ownCloudSDK

/// Reads shared credentials from keychain (e.g. filled by another app in the same keychain group).
/// Uses STXKeychainAccessGroupIdentifier from Info.plist (set by Fastlane from SHARED_KEYCHAIN_GROUP).
/// Keys: oc_base_url, oc_email, oc_password, ra_refresh_token, ra_client_id, ra_fav_device_certificate_common_name
public final class SharedCredentialsKeychain {
	private static let keychainAccount = "personalCloudFiles.sharedCredentials"

	private static var keychain: OCKeychain? {
		sharedKeychain
	}

	/// Keychain instance for the shared credentials group (STXKeychainAccessGroupIdentifier).
	private static let sharedKeychain: OCKeychain? = {
		guard let stxGroup = Bundle.main.object(forInfoDictionaryKey: "STXKeychainAccessGroupIdentifier") as? String,
		      !stxGroup.isEmpty,
		      !stxGroup.contains("$(")
		else { return nil }
		let prefix = OCAppIdentity.shared.appIdentifierPrefix ?? ""
		let fullIdentifier = prefix.isEmpty ? stxGroup : (prefix.hasSuffix(".") ? prefix + stxGroup : prefix + "." + stxGroup)
		return OCKeychain(accessGroupIdentifier: fullIdentifier)
	}()

	public struct OCCredentials {
		public let baseURL: URL
		public let email: String
		public let password: String

		public init(baseURL: URL, email: String, password: String) {
			self.baseURL = baseURL
			self.email = email
			self.password = password
		}
	}

	public struct RACredentials {
		public let refreshToken: String
		public let clientId: String
		public let favoriteDeviceCertificateCommonName: String

		public init(refreshToken: String, clientId: String, favoriteDeviceCertificateCommonName: String) {
			self.refreshToken = refreshToken
			self.clientId = clientId
			self.favoriteDeviceCertificateCommonName = favoriteDeviceCertificateCommonName
		}
	}

	// MARK: - Read

	/// Returns OC credentials if all required keys (oc_base_url, oc_email, oc_password) are present.
	public static func readOCCredentials() -> OCCredentials? {
		guard
			let baseURLString = readString(path: "oc_base_url"),
			let baseURL = parseBaseURL(baseURLString),
			let email = readString(path: "oc_email"),
			let password = readString(path: "oc_password"),
			!email.isEmpty,
			!password.isEmpty
		else { return nil }
		return OCCredentials(baseURL: baseURL, email: email, password: password)
	}

	/// Returns RA credentials if all required keys are present.
	public static func readRACredentials() -> RACredentials? {
		guard
			let refreshToken = readString(path: "ra_refresh_token"),
			let clientId = readString(path: "ra_client_id"),
			let favCN = readString(path: "ra_fav_device_certificate_common_name"),
			!refreshToken.isEmpty,
			!clientId.isEmpty,
			!favCN.isEmpty
		else { return nil }
		return RACredentials(
			refreshToken: refreshToken,
			clientId: clientId,
			favoriteDeviceCertificateCommonName: favCN
		)
	}

	private static func readString(path: String) -> String? {
		guard let data = keychain?.readDataFromKeychainItem(forAccount: keychainAccount, path: path) else { return nil }
		return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
			.nilIfEmpty
	}

	private static func parseBaseURL(_ raw: String) -> URL? {
		var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
			str = "https://" + str
		}
		guard var url = URL(string: str) else { return nil }
		// Ensure /files path for ownCloud
		if !url.path.hasSuffix("/files") {
			url = url.appendingPathComponent("files")
		}
		return url
	}

	// MARK: - Write (for testing / debug)

	/// Writes OC credentials to keychain. Use for testing auto-login without another app.
	public static func writeOC(baseURL: String, email: String, password: String) -> Bool {
		guard let kc = keychain else { return false }
		var str = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
		if !str.hasPrefix("http://") && !str.hasPrefix("https://") { str = "https://" + str }
		guard URL(string: str) != nil,
		      let urlData = str.data(using: .utf8),
		      let emailData = email.data(using: .utf8),
		      let passwordData = password.data(using: .utf8)
		else { return false }
		let r1 = kc.write(urlData, toKeychainItemForAccount: keychainAccount, path: "oc_base_url")
		let r2 = kc.write(emailData, toKeychainItemForAccount: keychainAccount, path: "oc_email")
		let r3 = kc.write(passwordData, toKeychainItemForAccount: keychainAccount, path: "oc_password")
		return r1 == nil && r2 == nil && r3 == nil
	}

	/// Writes RA credentials to shared keychain (for other apps / auto-login).
	public static func writeRA(refreshToken: String, clientId: String, favoriteDeviceCN: String) -> Bool {
		guard let kc = keychain,
		      let rt = refreshToken.data(using: .utf8),
		      let cid = clientId.data(using: .utf8),
		      let cn = favoriteDeviceCN.data(using: .utf8)
		else { return false }
		let r1 = kc.write(rt, toKeychainItemForAccount: keychainAccount, path: "ra_refresh_token")
		let r2 = kc.write(cid, toKeychainItemForAccount: keychainAccount, path: "ra_client_id")
		let r3 = kc.write(cn, toKeychainItemForAccount: keychainAccount, path: "ra_fav_device_certificate_common_name")
		return r1 == nil && r2 == nil && r3 == nil
	}

	// MARK: - Debug

	/// Prints current contents of the shared credentials keychain (for debugging).
	/// Sensitive values (password, refresh_token) are masked.
	public static func printContents() {
		let sensitiveKeys: Set<String> = ["oc_password", "ra_refresh_token"]
		let keys = [
			"oc_base_url",
			"oc_email",
			"oc_password",
			"ra_refresh_token",
			"ra_client_id",
			"ra_fav_device_certificate_common_name"
		]
		print("[SharedCredentialsKeychain] Contents:")
		for key in keys {
			if let value = readString(path: key) {
				let display = sensitiveKeys.contains(key) ? "***" : value
				print("  \(key): \(display)")
			} else {
				print("  \(key): (absent)")
			}
		}
	}

	// MARK: - Clear (optional, after successful use)

	public static func clearOCCredentials() {
		_ = keychain?.removeItem(forAccount: keychainAccount, path: "oc_base_url")
		_ = keychain?.removeItem(forAccount: keychainAccount, path: "oc_email")
		_ = keychain?.removeItem(forAccount: keychainAccount, path: "oc_password")
	}

	public static func clearRACredentials() {
		_ = keychain?.removeItem(forAccount: keychainAccount, path: "ra_refresh_token")
		_ = keychain?.removeItem(forAccount: keychainAccount, path: "ra_client_id")
		_ = keychain?.removeItem(forAccount: keychainAccount, path: "ra_fav_device_certificate_common_name")
	}
}

private extension String {
	var nilIfEmpty: String? {
		isEmpty ? nil : self
	}
}
