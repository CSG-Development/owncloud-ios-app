import UIKit
import Combine
import ownCloudSDK
import ownCloudAppShared

protocol CodeVerificationViewModelEventHandler: AnyObject {
	func handle(_ event: CodeVerificationViewModel.Event)
}

private enum Constants {
    static let codeLength: Int = 6
}

final public class CodeVerificationViewModel {
	enum Event {
		case verifyTap
		case resetPasswordTap
		case settingsTap
	}

	enum CodeVerificationError {
		case codeExpired
		case codeInvalid
		case emailNotRegistered

		case connectionFailed
		case tooManyRequests
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
	@Published private(set) var errors: [CodeVerificationError] = []

	private var cancellables = Set<AnyCancellable>()

	var codeLength: Int {
		Constants.codeLength
	}

	private var raService: RemoteAccessService {
		HCContext.shared.remoteAccessService
	}

	init(
		eventHandler: CodeVerificationViewModelEventHandler,
		email: String,
		reference: String? = nil,
		shouldRequestCodeOnInit: Bool = true
	) {
		self.eventHandler = eventHandler
		self.email = email
		self.reference = reference

        Publishers.CombineLatest($code.removeDuplicates(), $isExpired.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] code, isExpired in
                self?.isValidateEnabled = (code.count == Constants.codeLength) && !isExpired
            }
            .store(in: &cancellables)

		if shouldRequestCodeOnInit {
			Task {
				await requestEmailCode(email)
			}
		}
	}

	private func requestEmailCode(_ email: String) async {
		do {
			let response = try await raService.sendEmailCode(email: email)
			await MainActor.run {
				self.reference = response.reference
				Log.debug("[STX]: Code sent. Saving reference.")
			}
		} catch let error {
			await MainActor.run {
				Log.debug("[STX]: Code sending failed \(error)")
				self.handleError(error)
			}
		}
	}

    func didTapValidate() {
        guard
			code.count == Constants.codeLength,
			let reference
		else {
			return
		}

		isLoading = true
		Task {
			do {
				try await raService.validateEmailCode(code: code, reference: reference)
				await MainActor.run {
					Log.debug("[STX]: Code verification succeeded.")
					eventHandler.handle(.verifyTap)
				}
			} catch let error {
				await MainActor.run {
					Log.debug("[STX]: Code verification failed \(error)")
					handleError(error)
				}
			}			
		}
	}

	private func handleError(_ error: Error) {
		guard
			let raError = error as? RemoteAccessServiceError,
			case let .apiError(raAPIError) = raError
		else {
			self.errors = [.connectionFailed]
			return
		}

		switch raAPIError {
			case .tooManyRequests:
				self.errors = [.tooManyRequests]

			case .forbidden,
				 .internalServerError:
				self.errors = [.connectionFailed]

			case let .unauthorized(e):
				switch e.kind {
					case .codeExpired:
						self.errors = [.codeExpired]

					case .codeInvalid:
						self.errors = [.codeInvalid]

					case .emailNotRegistered:
						self.errors = [.emailNotRegistered]

					default:
						self.errors = [.connectionFailed]
				}
			default:
				self.errors = [.connectionFailed]
		}
	}

	public func didTapResendCode() {
        resetErrors()

		Task {
			await requestEmailCode(email)
		}
	}

	func didTapSkip() {
		eventHandler.handle(.verifyTap)
	}

	func resetErrors() {
		errors = []
	}
}
