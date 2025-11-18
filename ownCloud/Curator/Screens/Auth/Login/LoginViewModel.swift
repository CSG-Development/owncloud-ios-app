import UIKit
import Combine
import ownCloudSDK
import ownCloudAppShared

protocol LoginViewModelEventHandler: AnyObject {
	func handle(_ event: LoginViewModel.Event)
}

final public class LoginViewModel {
	enum Step {
		case emailEntry
		case deviceSelection
	}

    enum Event {
        case loginTap
        case resetPasswordTap
		case oldLoginTap
        case settingsTap
        case emailVerification(email: String)
        case backToEmail
    }

	enum LoginError {
		case authenticationFailed
		case serverNotFound
	}

	private let eventHandler: LoginViewModelEventHandler

	// Inputs
	@Published var username: String = ""
	@Published var password: String = ""

	// Outputs
	@Published private(set) var isLoginEnabled: Bool = true
	@Published private(set) var isLoading: Bool = false
	@Published private(set) var errors: [LoginError] = []
	@Published private(set) var step: Step = .emailEntry
    @Published private(set) var deviceItems: [String] = []
    @Published var selectedDeviceIndex: Int?
    @Published private(set) var isDetectingDevices: Bool = false

	private var cancellables = Set<AnyCancellable>()

	var bookmark: OCBookmark

	private var raService: RemoteAccessService {
		HCContext.shared.remoteAccessService
	}

	private var deviceReachabilityService: DeviceReachabilityService {
		HCContext.shared.deviceReachabilityService
	}

	private var preferences: HCPreferences {
		HCContext.shared.preferences
	}

	private var _cookieStorage : OCHTTPCookieStorage?
	var cookieStorage : OCHTTPCookieStorage? {
		if _cookieStorage == nil, let cookieSupportEnabled = OCCore.classSetting(forOCClassSettingsKey: .coreCookieSupportEnabled) as? Bool, cookieSupportEnabled == true {
			_cookieStorage = OCHTTPCookieStorage()
		}

		return _cookieStorage
	}

	// Progress to the next login step after email verification
	func advanceToDeviceSelection() {
		Log.debug("[STX]: Advance to device selection step")
		step = .deviceSelection
	}

    func backToEmailEntry() {
		Log.debug("[STX]: Going back to email entry")
        step = .emailEntry
        eventHandler.handle(.backToEmail)
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

        Publishers
            .CombineLatest3($username, $password, $step)
			.receive(on: RunLoop.main)
			.sink(receiveValue: { [weak self] username, password, _ in
				guard let self else { return }
				switch step {
					case .emailEntry:
						self.isLoginEnabled = self.isValidEmail(username)
					case .deviceSelection:
                        self.isLoginEnabled = (self.selectedDeviceIndex != nil) && !password.isEmpty
				}
			})
			.store(in: &cancellables)

        $selectedDeviceIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.step == .deviceSelection {
                    self.isLoginEnabled = (self.selectedDeviceIndex != nil) && !self.password.isEmpty
                }
            }
            .store(in: &cancellables)

        $password
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.step == .deviceSelection {
                    self.isLoginEnabled = (self.selectedDeviceIndex != nil) && !self.password.isEmpty
                }
            }
            .store(in: &cancellables)

        $step
            .removeDuplicates()
            .sink { [weak self] step in
                if case .deviceSelection = step { self?.loadDevices() }
            }
            .store(in: &cancellables)
	}

	private func isValidEmail(_ email: String) -> Bool {
		let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
		return email.range(of: pattern, options: .regularExpression) != nil
	}

	func login(url: URL) {
		Log.debug("[STX]: Starting login")
		// TODO: Refactor during login from invite implementation.
		guard isLoginEnabled, !isLoading else { return }
		isLoading = true

		bookmark.url = url
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
						if let username, !username.isEmpty {
							self.preferences.currentEmail = username
						}
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
		Log.debug("[STX]: Did tap login")
        resetErrors()
        switch step {
            case .emailEntry:
				sendEmailVerificationIfNeeded()
            case .deviceSelection:
				Task {
					await self.prepareAddressAndLoginForSelectedDevice()
				}
        }
    }

    // MARK: - Devices Merge (RA + mDNS)
    private var mergedDevices: [DeviceReachabilityService.MergedDevice] = []

    private func loadDevices() {
        Log.debug("[STX]: Starting devices load")
        isDetectingDevices = true
        deviceItems = []
        // keep current selection until we have a non-empty devices list or confirmed empty

		Task { [weak self, username] in
			guard let self else { return }
			let merged = (try? await self.deviceReachabilityService.getMergedDevices(email: username)) ?? []

			await MainActor.run {
				self.isDetectingDevices = false
				self.mergedDevices = merged
				let previousSelection = self.selectedDeviceIndex
				self.deviceItems = merged.map { $0.remoteDevice?.friendlyName ?? $0.localDevice?.name ?? "" }
				if let sel = previousSelection, sel < self.deviceItems.count {
					self.selectedDeviceIndex = sel
				} else if self.deviceItems.isEmpty {
					self.selectedDeviceIndex = nil
				} else if previousSelection == nil {
					self.selectedDeviceIndex = 0
				}
			}
		}
    }

    func refreshDevices() {
		Log.debug("[STX]: Refreshing devices.")
		resetErrors()
        loadDevices()
    }

	private func sendEmailVerificationIfNeeded() {
		guard !username.isEmpty else { return }
		Log.debug("[STX]: Username is not empty. Proceeding with email code.")

		raService.ensureAuthenticated(email: username) { [weak self] result in
			guard let self else { return }

			switch result {
				case .success:
					Log.debug("[STX]: Tokens exist and valid. Going to login step")
					self.advanceToDeviceSelection()

				case .failure(let error):
					Log.debug("[STX]: Tokens missing or invalid. Error \(error). Sending email code.")
					self.eventHandler.handle(.emailVerification(email: self.username))
			}
		}
	}

	private func orderPaths(_ paths: [RemoteDevice.Path]) -> [RemoteDevice.Path] {
		func priority(for kind: RemoteDevice.Path.Kind) -> Int {
			switch kind {
				case .local: return 0
				case .public: return 1
				case .remote: return 2
			}
		}
		return paths.sorted { a, b in
			let pa = priority(for: a.kind)
			let pb = priority(for: b.kind)
			if pa != pb { return pa < pb }
			let aa = "\(a.address):\(a.port ?? -1)"
			let bb = "\(b.address):\(b.port ?? -1)"
			return aa.localizedCaseInsensitiveCompare(bb) == .orderedAscending
		}
	}

	private func prepareAddressAndLoginForSelectedDevice() async {
		Log.debug("[STX]: Composing device URL")
        guard let idx = selectedDeviceIndex, idx < mergedDevices.count else { return }
        let device = mergedDevices[idx]

		// Ensure probes are fresh before selecting best path
		await deviceReachabilityService.reprobeExistingPaths()
		guard
			let bestPath = await deviceReachabilityService.currentBestPath(for: device),
			let url = bestPath.url?.appendingPathComponent("files")
		else {
			errors = [.serverNotFound]
			return
		}
		// Persist current device identification and email for reprobe on relaunch
		let cn = device.remoteDevice?.certificateCommonName ?? device.localDevice?.certificateCommonName
		if let cn {
			HCContext.shared.preferences.currentCertificateCN = cn
			if let remote = device.remoteDevice {
				let savedPaths: [HCPreferences.SavedConnectedDevice.SavedPath] = remote.paths.map {
					let kind: HCPreferences.SavedConnectedDevice.SavedPath.Kind
					switch $0.kind {
						case .local: kind = .local
						case .public: kind = .public
						case .remote: kind = .remote
					}
					return .init(kind: kind, address: $0.address, port: $0.port)
				}
				let saved = HCPreferences.SavedConnectedDevice(
					seagateDeviceID: remote.seagateDeviceID,
					certificateCommonName: remote.certificateCommonName,
					friendlyName: remote.friendlyName,
					hostname: remote.hostname,
					paths: savedPaths
				)
				HCContext.shared.preferences.currentConnectedDevice = saved
			}
		}
		if !username.isEmpty { HCContext.shared.preferences.currentEmail = username }
		login(url: url)
	}

	func didTapResetPassword() {
		Log.debug("[STX]: Reset password tap.")
		eventHandler.handle(.resetPasswordTap)
	}

	func didTapOldLogin() {
		Log.debug("[STX]: Old login tap.")
		eventHandler.handle(.oldLoginTap)
	}

	func didTapSettings() {
		Log.debug("[STX]: Setings tap.")
		eventHandler.handle(.settingsTap)
	}

	// Updated in CI. If you change something be sure to change the CI script as well.
	func fillTestInfo() {
		username = ""
		password = ""
	}
}
