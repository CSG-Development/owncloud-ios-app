import UIKit
import Combine
import ownCloudSDK
import ownCloudAppShared

protocol OldLoginViewModelEventHandler: AnyObject {
	func handle(_ event: OldLoginViewModel.Event)
}

final public class OldLoginViewModel {
	enum Event {
		case loginTap
		case resetPasswordTap
		case settingsTap
	}

	enum OldLoginError {
		case authenticationFailed
		case serverNotFound
	}

	private let eventHandler: OldLoginViewModelEventHandler

	// Inputs
	@Published var username: String = ""
	@Published var password: String = ""
	@Published var address: String = ""

	// Outputs
	@Published private(set) var isLoginEnabled: Bool = true
	@Published private(set) var isLoading: Bool = false
	@Published private(set) var errors: [OldLoginError] = []

	private var cancellables = Set<AnyCancellable>()

	var bookmark: OCBookmark

	private var _cookieStorage : OCHTTPCookieStorage?
	var cookieStorage : OCHTTPCookieStorage? {
		if _cookieStorage == nil, let cookieSupportEnabled = OCCore.classSetting(forOCClassSettingsKey: .coreCookieSupportEnabled) as? Bool, cookieSupportEnabled == true {
			_cookieStorage = OCHTTPCookieStorage()
		}

		return _cookieStorage
	}

	func instantiateConnection(for bmark: OCBookmark) -> OCConnection {
		let connection = OCConnection(bookmark: bmark)

		connection.hostSimulator = OCHostSimulatorManager.shared.hostSimulator(forLocation: .accountSetup, for: self)
		connection.cookieStorage = self.cookieStorage // Share cookie storage across all relevant connections

		return connection
	}

	init(eventHandler: OldLoginViewModelEventHandler) {
		self.eventHandler = eventHandler
		self.bookmark = OCBookmark()

		// Enable login when username isn't empty and password ≥ 8 chars
		Publishers
			.CombineLatest3($username, $password, $address)
			.map { !$0.isEmpty && !$1.isEmpty && !$2.isEmpty }
			.receive(on: RunLoop.main)
			.sink(receiveValue: { [weak self] isLoginEnabled in
				self?.isLoginEnabled = isLoginEnabled
			})
			.store(in: &cancellables)
	}

	func login() {
		Log.debug("[STX]: Starting login")		
		guard isLoginEnabled, !isLoading else { return }
		isLoading = true

		// For testing
		if !address.starts(with: "https://") && !address.starts(with: "http://") {
			address = "https://" + address
			Log.debug("[STX]: Appending https:// to entered address. Result: \(address)")
		}

		bookmark.url = URL(string: address)
		let connection = instantiateConnection(for: bookmark)
		OCConnection.setupHTTPPolicy = .allow
		Log.debug("[STX]: Calling OCConnection.prepareForSetup")
		connection.prepareForSetup(options: nil) { [weak self] (issue, _, supportedMethods, preferredAuthenticationMethods, generationOptions) in
			Log.debug("[STX]: prepareForSetup completion.")
			if let issues = issue?.issues {
				let issuesString = issues.map {
					"\($0.localizedTitle ?? "no title") - \($0.localizedDescription ?? "no description")"
				}.joined(separator: "\n")
				Log.debug("[STX]: Issues: \(issuesString)")
			}

			if let issues = issue?.issues, issues.contains(where: { $0.type == .error }) {
				self?.errors = [.serverNotFound]
				Log.debug("[STX]: There was an error preparing login. Aborting.")
				self?.isLoading = false
				return
			}

			Log.debug("[STX]: Checking supported authentication methods.")
			guard let supportedMethods else {
				Log.debug("[STX]: No supported methods found. Aborting.")
				self?.errors = [.serverNotFound]
				self?.isLoading = false
				return
			}

			Log.debug("[STX]: Supported methods: \(supportedMethods.map(\.rawValue).joined(separator: "\n"))")
			if let preferredAuthenticationMethods {
				Log.debug("[STX]: Preferred methods: \(preferredAuthenticationMethods.map(\.rawValue).joined(separator: "\n"))")
			}
			if let generationOptions {
				Log.debug("[STX]: Generation options: \(generationOptions)")
			}

			if supportedMethods.contains(.basicAuth) {
				self?.bookmark.authenticationMethodIdentifier = .basicAuth
				Log.debug("[STX]: Authenticating with basic auth method.")
				self?.authenticate(username: self?.username, password: self?.password)
			} else {
				Log.debug("[STX]: Basic auth is not supported. Aborting.")
				self?.errors = [.serverNotFound]
				self?.isLoading = false
			}
		}
	}

	func authenticate(username: String? = nil, password: String? = nil) {
		var options: [OCAuthenticationMethodKey: Any] = [:]

		let connection = instantiateConnection(for: bookmark)

		if let authMethodIdentifier = bookmark.authenticationMethodIdentifier {
			if OCAuthenticationMethod.isAuthenticationMethodPassphraseBased(authMethodIdentifier as OCAuthenticationMethodIdentifier) {
				Log.debug("[STX]: Authentication method passphrase based, providing username and password.")
				options[.usernameKey] = username ?? ""
				options[.passphraseKey] = password ?? ""
			} else {
				Log.debug("[STX]: Authentication method is not passphrase based.")
			}
		} else {
			Log.debug("[STX]: Bookmark doesnt have authentication method identifier.")
		}

		options[.requiredUsernameKey] = bookmark.userName

		// Pre-fill already provided username in case of a server locator being used
		if options[.requiredUsernameKey] == nil, let serverLocationUserName = bookmark.serverLocationUserName {
			options[.usernameKey] = serverLocationUserName
		}

		guard let bookmarkAuthenticationMethodIdentifier = bookmark.authenticationMethodIdentifier else {
			self.errors = [.serverNotFound]
			self.isLoading = false
			Log.debug("[STX]: Bookmark doesnt have authentication method identifier.")
			return
		}

		Log.debug("[STX]: Starting generation of authentication data.")
		connection.generateAuthenticationData(withMethod: bookmarkAuthenticationMethodIdentifier, options: options) { (error, authMethodIdentifier, authMethodData) in
			if error == nil, let authMethodIdentifier, let authMethodData {
				Log.debug("[STX]: Authentication generation succeeded.")
				self.bookmark.authenticationMethodIdentifier = authMethodIdentifier
				self.bookmark.authenticationData = authMethodData
				self.bookmark.scanForAuthenticationMethodsRequired = false

				Log.debug("[STX]: Retreiving available instances.")
				connection.retrieveAvailableInstances(options: options, authenticationMethodIdentifier: authMethodIdentifier, authenticationData: authMethodData, completionHandler: { error, instances in
					if error == nil, let instances, instances.count > 0 {
						Log.debug("[STX]: Instances: \(instances)")
					}

					if self.bookmark.isComplete {
						Log.debug("[STX]: Bookmark is complete. Adding bookmark")
						self.bookmark.authenticationDataStorage = .keychain // Commit auth changes to keychain
						OCBookmarkManager.shared.addBookmark(self.bookmark)
					} else {
						Log.debug("[STX]: Bookmark is not complete")
					}

				})
			} else {
				Log.debug("[STX]: Authentication generation failed with error: \(error?.localizedDescription ?? "")")
				self.errors = [.authenticationFailed]
				self.isLoading = false
			}
		}
	}

	func resetErrors() {
		errors = []
	}

	func didTapLogin() {
		resetErrors()
		login()
	}

	func didTapResetPassword() {
		eventHandler.handle(.resetPasswordTap)
	}

	func didTapSettings() {
		eventHandler.handle(.settingsTap)
	}

	// Updated in CI. If you change something be sure to change the CI script as well.
	func fillTestInfo() {
		username = ""
		password = ""
		address = ""
	}
}
