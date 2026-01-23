import UIKit
import Combine
import ownCloudSDK
import ownCloudAppShared

private enum Constants {
    static let codeLength: Int = 6
}

final public class CodeVerificationCardViewModel {
	// Inputs
	@Published var code: String = ""

	// Outputs
	@Published private(set) var isValidateEnabled: Bool = true
	@Published private(set) var isResendHidden: Bool = false
	@Published private(set) var isValidateHidden: Bool = false
	@Published private(set) var isLoaderHidden: Bool = true
	@Published private(set) var shouldHighlightError: Bool = false
	@Published private(set) var errorMessage: String?

	private var cancellables = Set<AnyCancellable>()

	private var onSkip: (() -> Void)?
	private var onValidate: ((String) -> Void)?
	private var onResend: (() -> Void)?

	var codeLength: Int {
		Constants.codeLength
	}

	private let codeVerificationService: CodeVerificationService

	init(
		codeVerificationService: CodeVerificationService,
		onSkip: (() -> Void)?,
		onValidate: ((String) -> Void)?,
		onResend: (() -> Void)?
	) {
		self.codeVerificationService = codeVerificationService
		self.onSkip = onSkip
		self.onValidate = onValidate
		self.onResend = onResend

		Publishers.CombineLatest3(
			$code.removeDuplicates(),
			codeVerificationService.$error.eraseToAnyPublisher(),
			codeVerificationService.$isLoading.eraseToAnyPublisher()
		)
		.receive(on: RunLoop.main)
		.sink { [weak self] code, error, isLoading in
			guard let self else { return }
			let isExpired = self.isExpiredError(error)

			self.isLoaderHidden = !isLoading
			self.isValidateEnabled = (code.count == Constants.codeLength) && !isExpired

			self.isValidateHidden = isExpired || isLoading
			self.isResendHidden = !isExpired || isLoading

			self.handleError(error)
		}
		.store(in: &cancellables)
	}

	func onCodeFocus() {
		guard let error = codeVerificationService.error else {
			codeVerificationService.resetError()
			return
		}
		guard let raServiceError = error as? RemoteAccessServiceError else {
			// Do not reset.
			return
		}
		switch raServiceError {
			case let .apiError(raAPIError):
				switch raAPIError {
					case .tooManyRequests:
						break // Do not reset.

					case .forbidden,
						 .internalServerError:
						break // Do not reset.

					case let .unauthorized(e):
						switch e.kind {
							case .codeExpired,
								 .codeInvalid,
								 .emailNotRegistered:
								codeVerificationService.resetError()
							default:
								break // Do not reset.
						}
					default:
						break // Do not reset.
				}
			default:
				break // Do not reset
		}
	}

	func didTapValidate() {
		guard code.count == Constants.codeLength else { return }

		onValidate?(code)
	}

	func didTapResendCode() {
		resetError()

		onResend?()
	}

	func didTapSkip() {
		onSkip?()
	}

	func resetError() {
		errorMessage = nil
		shouldHighlightError = false
		codeVerificationService.resetError()
	}

	private func isExpiredError(_ error: Error?) -> Bool {
		guard let error else { return false }

		if let raError = error as? RemoteAccessServiceError,
		   case let .apiError(raAPIError) = raError,
		   case let .unauthorized(e) = raAPIError,
		   case .codeExpired = e.kind {
			return true
		}
		return false
	}

	private func handleError(_ error: Error?) {
		self.shouldHighlightError = false
		self.errorMessage = nil

		guard let error else { return }
		// Default
		self.errorMessage = HCL10n.Auth.CodeVerification.connectionError

		guard
			let raError = error as? RemoteAccessServiceError,
			case let .apiError(raAPIError) = raError
		else {
			return
		}

		switch raAPIError {
			case .tooManyRequests:
				self.errorMessage = HCL10n.Auth.CodeVerification.tooManyRequestsError

			case let .unauthorized(e):
				switch e.kind {
					case .codeExpired:
						self.errorMessage = HCL10n.Auth.CodeVerification.codeExpiredError
						self.shouldHighlightError = true

					case .codeInvalid:
						self.errorMessage = HCL10n.Auth.CodeVerification.invalidCodeError
						self.shouldHighlightError = true

					default:
						break
				}
			default:
				break
		}
	}
}
