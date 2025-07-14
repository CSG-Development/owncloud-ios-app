import UIKit
import Combine

protocol LoginViewModelEventHandler: AnyObject {
	func handle(_ event: LoginViewModel.Event)
}

final public class LoginViewModel {
	enum Event {
		case loginTap
		case moreInfoTap
		case settingsTap
	}

	private let eventHandler: LoginViewModelEventHandler

	// Inputs
	@Published var username: String = ""
	@Published var password: String = ""

	// Outputs
	@Published private(set) var isLoginEnabled: Bool = true
	@Published private(set) var isLoading: Bool = false
	@Published private(set) var loginError: String?

	private var cancellables = Set<AnyCancellable>()

	init(eventHandler: LoginViewModelEventHandler) {
		self.eventHandler = eventHandler
		// Enable login when username isn't empty and password ≥ 8 chars
		Publishers
			.CombineLatest($username, $password)
			.map { !$0.isEmpty && $1.count >= 8 }
			.receive(on: RunLoop.main)
			.sink(receiveValue: { [weak self] isLoginEnabled in
				self?.isLoginEnabled = isLoginEnabled
			})			
			.store(in: &cancellables)
	}

	deinit {
		print("4242: LoginViewModel died")
	}

	func login() {
		guard isLoginEnabled, !isLoading else { return }
		loginError = nil
		isLoading = true

		// Simulated network call
		Just((username, password))
			.delay(for: .seconds(1.0), scheduler: DispatchQueue.global())
			.tryMap { user, pass in
				if user == "demo" && pass == "password123" {
					return true
				} else {
					throw URLError(.userAuthenticationRequired)
				}
			}
			.receive(on: RunLoop.main)
			.sink { [weak self] completion in
				self?.isLoading = false
				if case .failure = completion {
					self?.loginError = "Invalid credentials"
				}
			} receiveValue: { success in
				print("✅ Login succeeded!")
			}
			.store(in: &cancellables)
	}

	func didTapLogin() {
		eventHandler.handle(.loginTap)
	}

	func didTapMoreInfo() {
		eventHandler.handle(.moreInfoTap)
	}

	func didTapSettings() {
		eventHandler.handle(.settingsTap)
	}
}
