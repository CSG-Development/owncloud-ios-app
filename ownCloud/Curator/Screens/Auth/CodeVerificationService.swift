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

	private var codeVerificationAnimator: CrossDissolveTransitioningDelegate?
	private weak var presentedController: UIViewController?
	private var code500Animator: CrossDissolveTransitioningDelegate?
	private weak var presentedCode500Controller: UIViewController?
	private weak var rootViewController: UIViewController?
	private var isPresenting: Bool = false
	private var pendingCompletions: [Completion] = []
	private var isSetup: Bool = false

	private init() {}

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

	/// Requests a verification code for the given email.
	/// The RemoteAccess call is centralized here so we can
	/// consistently handle RA-specific failures (e.g. HTTP 500).
	func requestEmailCode(
		email: String,
		onSuccess: @escaping (RAInitiateResponse) -> Void,
		onNonInternalServerError: @escaping (Error) -> Void,
		onInternalServerError: @escaping (RemoteAccessAPIError) -> Void,
		onUnknownEmailError: @escaping (RemoteAccessAPIError) -> Void
	) async {
		do {
			let response = try await raService.sendEmailCode(email: email)
			await MainActor.run {
				onSuccess(response)
			}
		} catch {
			guard let raServiceError = error as? RemoteAccessServiceError else {
				await MainActor.run { onNonInternalServerError(error) }
				return
			}

			switch raServiceError {
				case let .apiError(apiError):
					switch apiError {
						case let .internalServerError:
							await MainActor.run { onInternalServerError(apiError) }

						case let .unauthorized(error):
							if case .emailNotRegistered = error.kind {
								await MainActor.run { onUnknownEmailError(apiError) }
							} else {
								await MainActor.run { onNonInternalServerError(error) }
							}

						default:
							await MainActor.run { onNonInternalServerError(error) }
					}
				default:
					await MainActor.run { onNonInternalServerError(error) }
			}
		}
	}

	func requestEmailCodeWithUI(
		email: String,
		onSuccess: @escaping (RAInitiateResponse) -> Void,
		onNonInternalServerError: @escaping (Error) -> Void,
		onCancel: (() -> Void)? = nil
	) async {
		await requestEmailCode(
			email: email,
			onSuccess: onSuccess,
			onNonInternalServerError: onNonInternalServerError,
			onInternalServerError: { [weak self] _ in
				guard let self else { return }
				self.presentInternalServerError(
					onRetry: { [weak self] in
						guard let self else { return }
						Task {
							await self.requestEmailCodeWithUI(
								email: email,
								onSuccess: onSuccess,
								onNonInternalServerError: onNonInternalServerError,
								onCancel: onCancel
							)
						}
					},
					onCancel: { onCancel?() }
				)
			},
			onUnknownEmailError: { [weak self] _ in
				guard let self else { return }
				self.presentUnknownEmailError(
					onCancel: { onCancel?() }
				)
			}
		)
	}

	func requestEmailCodeWithUI(
		email: String,
		viewModel: CodeVerificationViewModel,
		onCancel: (() -> Void)? = nil
	) async {
		await requestEmailCodeWithUI(
			email: email,
			onSuccess: { [weak viewModel] response in
				guard let viewModel else { return }
				viewModel.updateReference(response.reference)
				Log.debug("[STX]: Code sent. Saving reference.")
			},
			onNonInternalServerError: { [weak viewModel] error in
				guard let viewModel else { return }
				Log.debug("[STX]: Code sending failed \(error)")
				viewModel.handleError(error)
			},
			onCancel: onCancel
		)
	}

	private func startEmailVerificationFlow(email: String) async {
		await requestEmailCodeWithUI(
			email: email,
			onSuccess: { [weak self] response in
				guard let self else { return }
				self.presentEmailVerification(
					email: email,
					reference: response.reference,
					configure: { _ in
						Log.debug("[STX]: Code sent. Saving reference.")
					}
				)
			},
			onNonInternalServerError: { [weak self] error in
				guard let self else { return }
				self.presentEmailVerification(
					email: email,
					configure: { viewModel in
						Log.debug("[STX]: Code sending failed \(error)")
						viewModel.handleError(error)
					}
				)
			},
			onCancel: { [weak self] in
				self?.finishCurrentFlow(isAuthenticated: false)
			}
		)
	}

	func validateEmailCode(
		code: String,
		reference: String,
		viewModel: CodeVerificationViewModel
	) async {
		await MainActor.run {
			viewModel.setLoading(true)
		}
		do {
			try await raService.validateEmailCode(code: code, reference: reference)
			await MainActor.run {
				Log.debug("[STX]: Code verification succeeded.")
				self.handle(.verifyTap)
				viewModel.setLoading(false)
			}
		} catch {
			await MainActor.run {
				Log.debug("[STX]: Code verification failed \(error)")
				viewModel.handleError(error)
				viewModel.setLoading(false)
			}
		}
	}

	func skipVerification() {
		handle(.verifyTap)
	}

	func presentUnknownEmailError(onCancel: @escaping () -> Void) {
		let vc = CodeUnknownEmailViewController(onCancel: onCancel)
		let animator = CrossDissolveTransitioningDelegate()
		vc.transitioningDelegate = animator
		vc.modalPresentationStyle = .custom
		code500Animator = animator
		presentedCode500Controller = vc
		topMostController(from: rootViewController)?.present(vc, animated: true)
	}

	func presentInternalServerError(
		onRetry: @escaping () -> Void,
		onCancel: @escaping () -> Void
	) {
		let vc = Code500ViewController(
			onRetry: onRetry,
			onCancel: onCancel
		)
		let animator = CrossDissolveTransitioningDelegate()
		vc.transitioningDelegate = animator
		vc.modalPresentationStyle = .custom
		code500Animator = animator
		presentedCode500Controller = vc
		topMostController(from: rootViewController)?.present(vc, animated: true)
	}

	private func presentEmailVerification(
		email: String,
		reference: String? = nil,
		configure: (CodeVerificationViewModel) -> Void
	) {
		let vm = CodeVerificationViewModel(
			eventHandler: self,
			email: email,
			reference: reference
		)
		configure(vm)

		let vc = CodeVerificationViewController(viewModel: vm)
		let animator = CrossDissolveTransitioningDelegate()
		vc.transitioningDelegate = animator
		vc.modalPresentationStyle = .custom
		codeVerificationAnimator = animator
		presentedController = vc
		topMostController(from: rootViewController)?.present(vc, animated: true)
	}

	private func finishCurrentFlow(isAuthenticated: Bool) {
		isPresenting = false
		let completions = pendingCompletions
		pendingCompletions = []
		completions.forEach { $0(isAuthenticated) }
	}

	private func topMostController(from controller: UIViewController?) -> UIViewController? {
		guard let controller else { return nil }
		var top = controller
		while let presented = top.presentedViewController {
			top = presented
		}
		return top
	}
}

// Allow external dismissal paths (e.g., overlay tap) to finish the flow
extension CodeVerificationService {
	func notifyDismissedExternally() {
		finishCurrentFlow(isAuthenticated: false)
	}
}

extension CodeVerificationService: CodeVerificationViewModelEventHandler {
	func handle(_ event: CodeVerificationViewModel.Event) {
		switch event {
			case .verifyTap:
				presentedController?.dismiss(animated: true, completion: { [weak self] in
					self?.finishCurrentFlow(isAuthenticated: true)
				})

			case .resetPasswordTap:
				break

			case .settingsTap:
				break
		}
	}
}
