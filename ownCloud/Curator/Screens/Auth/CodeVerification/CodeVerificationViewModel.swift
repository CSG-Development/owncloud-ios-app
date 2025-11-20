import UIKit
import Combine
import ownCloudSDK
import ownCloudAppShared

protocol CodeVerificationViewModelEventHandler: AnyObject {
	func handle(_ event: CodeVerificationViewModel.Event)
}

private enum Constants {
	static let codeValidityDuration: TimeInterval = 600.0
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
	private var reference: String?
	public let email: String

	// Inputs
	@Published var code: String = ""

	// Outputs
	@Published private(set) var isValidateEnabled: Bool = true
	@Published private(set) var isLoading: Bool = false
    @Published private(set) var isExpired: Bool = false
    public private(set) var codeSentAt: Date?
	@Published private(set) var errors: [CodeVerificationError] = []

	private var cancellables = Set<AnyCancellable>()

	var codeLength: Int {
		Constants.codeLength
	}

	private var raService: RemoteAccessService {
		HCContext.shared.remoteAccessService
	}

	init(eventHandler: CodeVerificationViewModelEventHandler, email: String) {
		self.eventHandler = eventHandler
		self.email = email

        Publishers.CombineLatest($code.removeDuplicates(), $isExpired.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] code, isExpired in
                self?.isValidateEnabled = (code.count == Constants.codeLength) && !isExpired
            }
            .store(in: &cancellables)

		requestEmailCode(email)
	}

	private func requestEmailCode(_ email: String) {
		raService.sendEmailCode(email: email) { result in
			switch result {
				case .success(let response):
					self.reference = response.reference
					self.codeSentAt = Date()
					Log.debug("[STX]: Code sent. Saving reference.")

				case .failure(let error):
					Log.debug("[STX]: Code sending failed \(error)")
					self.errors = [.serverNotFound]
			}
		}
	}

    func didTapValidate() {
        guard
			code.count == Constants.codeLength,
			let reference,
			let codeDate = codeSentAt
		else {
			return
		}

		let codeLifeSeconds = Date().timeIntervalSince1970 - codeDate.timeIntervalSince1970

		if codeLifeSeconds > Constants.codeValidityDuration {
			// Consider code as expired.
			self.errors = [.codeExpired]
			return
		}

		isLoading = true
		raService.validateEmailCode(code: code, reference: reference) { [weak self] result in
			guard let self else { return }
			self.isLoading = false
			switch result {
                case .success:
					eventHandler.handle(.verifyTap)

                case .failure(let error):
                    let ns = error as NSError
                    if ns.domain == "RemoteAccessAPI" && (ns.code == 410 || ns.code == 401 || ns.code == 498) {
                        self.errors = [.codeExpired]
                    } else {
                        self.errors = [.authenticationFailed]
                    }
			}
		}
	}

	public func didTapResendCode() {
        resetErrors()

		requestEmailCode(email)
	}

	func didTapSkip() {
		eventHandler.handle(.verifyTap)
	}

	func resetErrors() {
		errors = []
	}
}
