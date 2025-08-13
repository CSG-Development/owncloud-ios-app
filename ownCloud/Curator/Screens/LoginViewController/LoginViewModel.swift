import UIKit
import Combine
import ownCloudSDK

protocol LoginViewModelEventHandler: AnyObject {
	func handle(_ event: LoginViewModel.Event)
}

final public class LoginViewModel {
	enum Event {
		case loginTap
		case resetPasswordTap
		case settingsTap
	}

	enum LoginError {
		case authenticationFailed
		case serverNotFound
	}

	private let eventHandler: LoginViewModelEventHandler

	// Inputs
	@Published var username: String = "admin1"
	@Published var password: String = "admin"
	@Published var address: String = "http://192.168.88.29:18080"

	// Outputs
	@Published private(set) var isLoginEnabled: Bool = true
	@Published private(set) var isLoading: Bool = false
	@Published private(set) var errors: [LoginError] = []

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

	init(eventHandler: LoginViewModelEventHandler) {
		self.eventHandler = eventHandler
		self.bookmark = OCBookmark()

		// Enable login when username isn't empty and password ≥ 8 chars
		Publishers
			.CombineLatest($username, $password)
			.map { !$0.0.isEmpty }
			.receive(on: RunLoop.main)
			.sink(receiveValue: { [weak self] isLoginEnabled in
				self?.isLoginEnabled = isLoginEnabled
			})
			.store(in: &cancellables)
	}

	func login() {
		// TODO: Refactor during login from invite implementation.
		guard isLoginEnabled, !isLoading else { return }
		isLoading = true

		bookmark.url = URL(string: address)
		let connection = instantiateConnection(for: bookmark)
		OCConnection.setupHTTPPolicy = .allow
		connection.prepareForSetup(options: nil) { [weak self] (issue, _, _, preferredAuthenticationMethods, generationOptions) in
			if let issues = issue?.issues, issues.contains(where: { $0.type == .error }) {
				self?.errors = [.serverNotFound]
				self?.isLoading = false
				return
			}

			if let preferredAuthenticationMethods {
				self?.bookmark.authenticationMethodIdentifier = preferredAuthenticationMethods.first
				self?.authenticate(username: self?.username, password: self?.password)
			} else {
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
				options[.usernameKey] = username ?? ""
				options[.passphraseKey] = password ?? ""
			}
		}

		options[.requiredUsernameKey] = bookmark.userName

		// Pre-fill already provided username in case of a server locator being used
		if options[.requiredUsernameKey] == nil, let serverLocationUserName = bookmark.serverLocationUserName {
			options[.usernameKey] = serverLocationUserName
		}

		guard let bookmarkAuthenticationMethodIdentifier = bookmark.authenticationMethodIdentifier else {
			self.errors = [.serverNotFound]
			self.isLoading = false
			return
		}

		connection.generateAuthenticationData(withMethod: bookmarkAuthenticationMethodIdentifier, options: options) { (error, authMethodIdentifier, authMethodData) in
			if error == nil, let authMethodIdentifier, let authMethodData {
				self.bookmark.authenticationMethodIdentifier = authMethodIdentifier
				self.bookmark.authenticationData = authMethodData
				self.bookmark.scanForAuthenticationMethodsRequired = false

				// Retrieve available instances for this account to chose from
				connection.retrieveAvailableInstances(options: options, authenticationMethodIdentifier: authMethodIdentifier, authenticationData: authMethodData, completionHandler: { error, instances in
					if error == nil, let instances, instances.count > 0 {
//						self.instances = instances
					}

					if self.bookmark.isComplete {
						self.bookmark.authenticationDataStorage = .keychain // Commit auth changes to keychain
						OCBookmarkManager.shared.addBookmark(self.bookmark)
					}

				})
			} else {
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
}
