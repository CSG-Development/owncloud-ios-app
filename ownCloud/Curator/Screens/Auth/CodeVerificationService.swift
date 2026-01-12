import UIKit
import ownCloudAppShared

public final class CodeVerificationService {
	public static let shared = CodeVerificationService()

	public typealias Completion = () -> Void

	private var deviceReachabilityService: DeviceReachabilityService {
		HCContext.shared.deviceReachabilityService
	}

	private var codeVerificationAnimator: CrossDissolveTransitioningDelegate?
	private weak var presentedController: UIViewController?
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
				self?.requestEmailVerification(email: email, reference: nil, completion: nil)
			}
		}
	}

	/// Request the code verification flow. If a flow is already visible, the completion is queued
	/// and will fire once the active flow finishes.
	public func requestEmailVerification(
		email: String,
		reference: String?,
		completion: Completion?
	) {
		if let completion { pendingCompletions.append(completion) }
		guard isPresenting == false else { return }
		isPresenting = true
		presentEmailVerification(email: email, reference: reference)
	}

	private func presentEmailVerification(email: String, reference: String?) {
		let vm = CodeVerificationViewModel(
			eventHandler: self,
			email: email,
			reference: reference,
			shouldRequestCodeOnInit: reference == nil
		)
		let vc = CodeVerificationViewController(viewModel: vm)
		let animator = CrossDissolveTransitioningDelegate()
		vc.transitioningDelegate = animator
		vc.modalPresentationStyle = .custom
		codeVerificationAnimator = animator
		presentedController = vc
		topMostController(from: rootViewController)?.present(vc, animated: true)
	}

	private func finishCurrentFlow() {
		isPresenting = false
		let completions = pendingCompletions
		pendingCompletions = []
		completions.forEach { $0() }
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

extension CodeVerificationService: CodeVerificationViewModelEventHandler {
	func handle(_ event: CodeVerificationViewModel.Event) {
		switch event {
			case .verifyTap:
				presentedController?.dismiss(animated: true, completion: { [weak self] in
					self?.finishCurrentFlow()
				})

			case .resetPasswordTap:
				break

			case .settingsTap:
				break
		}
	}
}
