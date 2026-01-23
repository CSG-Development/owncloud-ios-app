import UIKit
import ownCloudAppShared

public final class CodeVerificationService {
	public static let shared = CodeVerificationService()

	public typealias Completion = (Bool) -> Void

	private var raService: RemoteAccessService {
		HCContext.shared.remoteAccessService
	}

	private var deviceReachabilityService: DeviceReachabilityService {
		HCContext.shared.deviceReachabilityService
	}

	private var animator: CrossDissolveTransitioningDelegate?
	private weak var rootViewController: UIViewController?
	private var isPresenting: Bool = false
	private weak var container: CodeVerificationContainerViewController?
	private var pendingCompletions: [Completion] = []
	private var isSetup: Bool = false
	private var currentEmail: String?
	private var reference: String?

	private var codeVerificationVM: CodeVerificationCardViewModel!
	private var codeVerificationVC: CodeVerificationCardViewController!
	private var code500CardVC: CodeVerification500CardViewController!
	private var codeUnknownEmailCardVC: CodeVerificationUnknownEmailCardViewController!

	@Published private(set) var isLoading: Bool = false
	@Published private(set) var error: Error?

	private init() {
		buildVCs()
	}

	public func setup(with rootViewController: UIViewController) {
		guard isSetup == false else { return }
		isSetup = true
		self.rootViewController = rootViewController
		Task {
			await deviceReachabilityService.observeEmailValidationRequest { [weak self] email in
				self?.requestEmailVerification(email: email, completion: { [weak self] isAuthenticated in
					guard isAuthenticated else { return }
					Task {
						await self?.deviceReachabilityService.forceReloadDevices()
					}
				})
			}
		}
	}

	/// Request the code verification flow. If a flow is already visible, the completion is queued
	/// and will fire once the active flow finishes.
	public func requestEmailVerification(
		email: String,
		completion: Completion?
	) {
		if let completion { pendingCompletions.append(completion) }
		guard isPresenting == false else { return }
		isPresenting = true

		Task {
			await self.startEmailVerificationFlow(email: email)
		}
	}

	/// Indicates whether a code verification flow is currently visible.
	public var isPresentingVerification: Bool {
		return isPresenting
	}

	private func _requestEmailCode(
		email: String,
		onSuccess: @escaping (RAInitiateResponse) async -> Void,
		onNonInternalServerError: @escaping (Error) async -> Void,
		onInternalServerError: @escaping (RemoteAccessAPIError) async -> Void,
		onUnknownEmailError: @escaping (RemoteAccessAPIError) async -> Void
	) async {
		self.isLoading = true
		self.error = nil
		do {
			let response = try await raService.sendEmailCode(email: email)
			self.isLoading = false
			await onSuccess(response)
		} catch let error {
			self.isLoading = false
			self.error = error
			guard let raServiceError = error as? RemoteAccessServiceError else {
				await onNonInternalServerError(error)
				return
			}

			switch raServiceError {
				case let .apiError(apiError):
					switch apiError {
						case .internalServerError:
							await onInternalServerError(apiError)

						case let .unauthorized(error):
							if case .emailNotRegistered = error.kind {
								await onUnknownEmailError(apiError)
							} else {
								await onNonInternalServerError(error)
							}

						default:
							await onNonInternalServerError(error)
					}
				default:
					await onNonInternalServerError(error)
			}
		}
	}

	private func startEmailVerificationFlow(email: String) async {
		await MainActor.run {
			self.reference = nil
			self.currentEmail = email
			let vc = CodeVerificationContainerViewController(codeVerificationService: self)
			container = vc
			let animator = CrossDissolveTransitioningDelegate()
			vc.transitioningDelegate = animator
			vc.modalPresentationStyle = .custom
			self.animator = animator

			topMostController(from: rootViewController)?.present(vc, animated: true)
		}
		await requestEmailCode(email)
	}

	private func requestEmailCode(_ email: String) async {
		self.error = nil
		await MainActor.run {
			self.container?.setContent(CodeVerificationLoaderViewController())
		}
		await self._requestEmailCode(email: email) { resp in
			self.reference = resp.reference
			await MainActor.run {
				self.container?.setContent(self.codeVerificationVC)
			}
		} onNonInternalServerError: { error in
			await MainActor.run {
				self.container?.setContent(self.codeVerificationVC)
			}
		} onInternalServerError: { error in
			await MainActor.run {
				self.container?.setContent(self.code500CardVC)
			}
		} onUnknownEmailError: { error in
			await MainActor.run {
				self.container?.setContent(self.codeUnknownEmailCardVC)
			}
		}
	}

	func buildCode500CardViewController() -> CodeVerification500CardViewController {
		CodeVerification500CardViewController(
			onRetry: { [weak self] in
				self?.onResendTap()
			}, onCancel: { [weak self] in
				self?.onCancelTap()
			}
		)
	}

	func buildCodeUnknownEmailCardViewController() -> CodeVerificationUnknownEmailCardViewController {
		CodeVerificationUnknownEmailCardViewController(
			onCancel: { [weak self] in
				self?.onCancelTap()
			}
		)
	}

	func buildCodeVerificationViewController() -> (CodeVerificationCardViewModel, CodeVerificationCardViewController) {
		let vm = CodeVerificationCardViewModel(
			codeVerificationService: self,
			onSkip: { [weak self] in
				self?.onSkipTap()
			},
			onValidate: { [weak self] code in
				self?.onValidateTap(code)
			},
			onResend: { [weak self] in
				self?.onResendTap()
			}
		)
		return (vm, CodeVerificationCardViewController(viewModel: vm))
	}

	public func onResendTap() {
		guard let currentEmail else {
			Log.debug("[STX]: Resend tap received but we have no email saved.")
			return
		}
		Task {
			await requestEmailCode(currentEmail)
		}
	}

	public func onValidateTap(_ code: String) {
		guard let reference else {
			Log.debug("[STX]: Validate tap received but we have no reference.")
			return
		}
		Task {
			self.isLoading = true
			self.error = nil
			do {
				try await raService.validateEmailCode(code: code, reference: reference)
				self.isLoading = false
				await MainActor.run {
					self.dismiss(isAuthenticated: true)
				}
			} catch let error {
				self.error = error
				self.isLoading = false
			}
		}
	}

	public func onOverlayTap() {
		dismiss(isAuthenticated: false)
	}

	public func onCancelTap() {
		dismiss(isAuthenticated: false)
	}

	public func onSkipTap() {
		dismiss(isAuthenticated: false)
	}

	public func resetError() {
		self.error = nil
	}

	private func dismiss(isAuthenticated: Bool) {
		container?.dismiss(animated: true) {
			self.isPresenting = false
			self.reference = nil
			self.currentEmail = nil
			self.resetError()
			self.buildVCs()
			let completions = self.pendingCompletions
			self.pendingCompletions = []
			completions.forEach { $0(isAuthenticated) }
		}
	}

	private func topMostController(from controller: UIViewController?) -> UIViewController? {
		guard let controller else { return nil }
		var top = controller
		while let presented = top.presentedViewController {
			top = presented
		}
		return top
	}

	private func buildVCs() {
		let (codeVerificationVM, codeVerificationVC) = buildCodeVerificationViewController()
		self.codeVerificationVM = codeVerificationVM
		self.codeVerificationVC = codeVerificationVC

		code500CardVC = buildCode500CardViewController()
		codeUnknownEmailCardVC = buildCodeUnknownEmailCardViewController()
	}
}
