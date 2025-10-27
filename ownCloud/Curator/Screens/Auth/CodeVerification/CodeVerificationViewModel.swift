import UIKit
import Combine
import ownCloudSDK
import ownCloudAppShared

protocol CodeVerificationViewModelEventHandler: AnyObject {
	func handle(_ event: CodeVerificationViewModel.Event)
}

private enum Constants {
	static let codeValidityDuration: Int = 600
    static let codeLength: Int = 6
}

final public class CodeVerificationViewModel {
	enum Event {
		case verifyTap
		case resetPasswordTap
		case settingsTap
	}

	enum CodeVerificationError {
		case authenticationFailed
		case serverNotFound
		case codeExpired
	}

	private let eventHandler: CodeVerificationViewModelEventHandler
	private var reference: String
	public let email: String

	// Inputs
	@Published var code: String = ""

	// Outputs
	@Published private(set) var isValidateEnabled: Bool = true
	@Published private(set) var isLoading: Bool = false
	@Published private(set) var isExpired: Bool = false
	@Published private(set) var remainingSeconds: Int = Constants.codeValidityDuration
	@Published private(set) var errors: [CodeVerificationError] = []

	private var cancellables = Set<AnyCancellable>()
	private var timer: Timer? {
		willSet {
			if let timer, timer.isValid {
				timer.invalidate()
			}
		}
	}

	var codeLength: Int {
		Constants.codeLength
	}

	private var raService: RemoteAccessService {
		RemoteAccessService.shared
	}

	init(eventHandler: CodeVerificationViewModelEventHandler, reference: String, email: String) {
		self.eventHandler = eventHandler
		self.reference = reference
		self.email = email
        Publishers.CombineLatest($code.removeDuplicates(), $isExpired.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] code, isExpired in
                self?.isValidateEnabled = (code.count == Constants.codeLength) && !isExpired
            }
            .store(in: &cancellables)
	}

	func didTapValidate() {
        guard code.count == Constants.codeLength, !isExpired else { return }
		isLoading = true
		raService.validateEmailCode(code: code, reference: reference) { [weak self] result in
			guard let self else { return }
			self.isLoading = false
			switch result {
				case .success:
					eventHandler.handle(.verifyTap)

				case .failure:
					self.errors = [.authenticationFailed]
			}
		}
	}

	public func startTimer() {
		resetTimerState()
		timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] t in
			guard let self else { return }
			if self.remainingSeconds > 0 {
				self.remainingSeconds -= 1
				if self.remainingSeconds == 0 {
					self.isExpired = true
					self.errors = [.codeExpired]
					self.timer = nil
				}
			}
		})
	}

	public func didTapResendCode() {
		resetErrors()
		startTimer()

		raService.sendEmailCode(email: email) { [weak self] result in
			guard let self else { return }
			switch result {
				case .success(let response):
					self.reference = response.reference

				case .failure:
					self.errors = [.serverNotFound]
			}
		}
	}

	private func resetTimerState() {
		remainingSeconds = Constants.codeValidityDuration
		isExpired = false
	}

	deinit {
		timer = nil
	}

	func didTapSkip() {
		eventHandler.handle(.verifyTap)
	}

	func resetErrors() {
		errors = []
	}
}
