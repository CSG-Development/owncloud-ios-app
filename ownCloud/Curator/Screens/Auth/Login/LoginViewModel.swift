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
	@Published var address: String = ""

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
		RemoteAccessService.shared
	}

	private var mdnsService: MDNSService {
		MDNSService.shared
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
            .CombineLatest4($username, $password, $address, $step)
			.receive(on: RunLoop.main)
			.sink(receiveValue: { [weak self] username, password, address, _ in
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

	func login() {
		Log.debug("[STX]: Starting login")
		// TODO: Refactor during login from invite implementation.
		guard isLoginEnabled, !isLoading else { return }
		isLoading = true

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
//						self.instances = instances
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
		Log.debug("[STX]: Did tap login")
        resetErrors()
        switch step {
            case .emailEntry:
				sendEmailVerificationIfNeeded()
            case .deviceSelection:
                prepareAddressAndLoginForSelectedDevice()
        }
    }

    // MARK: - Devices Merge (RA + mDNS)
    private struct MergedDevice {
		let remoteDevice: RemoteDevice?
		let localDevice: LocalDevice?
    }
    private var mergedDevices: [MergedDevice] = []

    private func loadDevices() {
		Log.debug("[STX]: Starting devices load")
        isDetectingDevices = true
        deviceItems = []
        selectedDeviceIndex = nil
        raService.getRemoteDevices(email: username) { [weak self] result in
            guard let self else { return }

            let localDevices = mdnsService.currentDevices()
			Log.debug("[STX]: Got local: \(localDevices)")
            var deviceMap: [String: MergedDevice] = [:]

            if case let .success(remoteDevices) = result {
				Log.debug("[STX]: Got remote: \(remoteDevices)")
                for remoteDevice in remoteDevices {
                    deviceMap[remoteDevice.certificateCommonName] = MergedDevice(
                        remoteDevice: remoteDevice,
                        localDevice: nil
                    )
                }
            }

            for local in localDevices {
                if let certCN = local.certificateCommonName {
                    if deviceMap[certCN] == nil {
                        deviceMap[certCN] = MergedDevice(remoteDevice: nil, localDevice: local)
                    } else if var existing = deviceMap[certCN] {
                        existing = MergedDevice(remoteDevice: existing.remoteDevice, localDevice: local)
                        deviceMap[certCN] = existing
                    }
                }
            }

            self.isDetectingDevices = false

            let mergedArray = Array(deviceMap.values)
            self.mergedDevices = mergedArray.sorted { a, b in
                let nameA = a.remoteDevice?.friendlyName ?? a.localDevice?.name ?? ""
                let nameB = b.remoteDevice?.friendlyName ?? b.localDevice?.name ?? ""
                return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
            }
			Log.debug("[STX]: Merged devices: \(mergedArray)")
            self.deviceItems = self.mergedDevices.map { $0.remoteDevice?.friendlyName ?? $0.localDevice?.name ?? "" }
            if let sel = self.selectedDeviceIndex, sel < self.deviceItems.count {
                // keep
            } else {
                self.selectedDeviceIndex = self.deviceItems.isEmpty ? nil : 0
            }

            MDNSService.shared.onUpdate = { [weak self] locals in
                self?.mergeLocalDevices(locals)
            }
        }
    }

    private func mergeLocalDevices(_ locals: [LocalDevice]) {
        var map: [String: MergedDevice] = [:]
        for device in mergedDevices {
            if let certificateCommonName = device.remoteDevice?.certificateCommonName {
                map[certificateCommonName] = device
            } else if let certificateCommonName = device.localDevice?.certificateCommonName {
                map[certificateCommonName] = device
            } else if let name = device.localDevice?.name {
                map[name] = device
            }
        }

        for local in locals {
            guard let key = local.certificateCommonName ?? local.name as String? else { continue }
            if let existing = map[key] {
                map[key] = MergedDevice(remoteDevice: existing.remoteDevice, localDevice: local)
            } else {
                map[key] = MergedDevice(remoteDevice: nil, localDevice: local)
            }
        }

        let previousSelection = selectedDeviceIndex
        mergedDevices = Array(map.values).sorted { a, b in
            let nameA = a.remoteDevice?.friendlyName ?? a.localDevice?.name ?? ""
            let nameB = b.remoteDevice?.friendlyName ?? b.localDevice?.name ?? ""
            return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
        }
        deviceItems = mergedDevices.map { $0.remoteDevice?.friendlyName ?? $0.localDevice?.name ?? "" }
        if let sel = previousSelection, sel < deviceItems.count {
            selectedDeviceIndex = sel
        } else if deviceItems.isEmpty {
            selectedDeviceIndex = nil
        } else if previousSelection == nil {
            selectedDeviceIndex = 0
        }
    }

    func refreshDevices() {
		Log.debug("[STX]: Refreshing devices.")
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

    private func prepareAddressAndLoginForSelectedDevice() {
		Log.debug("[STX]: Composing device URL")
        guard let idx = selectedDeviceIndex, idx < mergedDevices.count else { return }
        let device = mergedDevices[idx]

		if let first = device.remoteDevice?.paths.first {
			let url = self.composeURL(address: first.address, port: first.port, path: "/files")
			self.address = url
			Log.debug("[STX]: URL: \(url)")
			self.login()
		} else if let host = device.localDevice?.host {
			let url = composeURL(address: host, port: device.localDevice?.port)
			self.address = url
			Log.debug("[STX]: URL: \(url)")
			self.login()
		} else {
			errors = [.serverNotFound]
		}
    }

    private func composeURL(address: String, port: Int?, path: String? = nil) -> String {
        let hostPort = port != nil ? "\(address):\(port!)" : address
        let withScheme: String = (hostPort.hasPrefix("http://") || hostPort.hasPrefix("https://")) ? hostPort : "https://\(hostPort)"
        guard let path, !path.isEmpty else { return withScheme }
        if withScheme.hasSuffix("/") {
            let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
            return withScheme + trimmed
        } else {
            let prefixed = path.hasPrefix("/") ? path : "/" + path
            return withScheme + prefixed
        }
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
		address = ""
	}
}
