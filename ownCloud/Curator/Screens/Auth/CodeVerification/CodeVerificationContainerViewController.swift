import UIKit
import ownCloudAppShared

final class CodeVerificationContainerViewController: UIViewController, Themeable {
	enum State {
		case unknownEmail
		case internalServerError
		case verifyCode
	}

	private lazy var overlay: HCOverlayView = {
		let overlayView = HCOverlayView()
		return overlayView
	}()

	private var containerController: ContainerController?
	private var containerStackView: UIStackView!
	private lazy var containerView: UIView = {
		let containerView = UIView()
		containerView.backgroundColor = .clear
		containerView.setContentHuggingPriority(.defaultHigh, for: .vertical)
		containerView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
		containerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		containerView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
		return containerView
	}()

	init() {
		super.init(nibName: nil, bundle: nil)
	}

	deinit {
		Theme.shared.unregister(client: self)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		Theme.shared.register(client: self, applyImmediately: true)
		setupUI()
	}

	private func setupUI() {
		view.backgroundColor = .clear

		view.addSubview(overlay)
		overlay.snp.makeConstraints { $0.edges.equalToSuperview() }

		let containerStackView = UIStackView()
		containerStackView.axis = .vertical
		containerStackView.spacing = 0
		containerStackView.isLayoutMarginsRelativeArrangement = true
		containerStackView.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
		containerStackView.alignment = .center
		view.addSubview(containerStackView)
		self.containerStackView = containerStackView
		// Outside/backdrop taps must not dismiss OTP — critical security prompt.
		view.keyboardLayoutGuide.followsUndockedKeyboard = true
		containerStackView.snp.makeConstraints {
			$0.top.equalTo(view.safeAreaLayoutGuide)
			$0.leading.trailing.equalToSuperview()
			$0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
		}

		let topSpacer = HCSpacerView(nil, .vertical)
		topSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
		let bottomSpacer = HCSpacerView(nil, .vertical)
		bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)

		containerStackView.addArrangedSubviews([
			topSpacer,
			containerView,
			bottomSpacer
		])

		containerView.snp.makeConstraints {
			$0.leading.greaterThanOrEqualTo(view.safeAreaLayoutGuide).offset(24)
			$0.trailing.lessThanOrEqualTo(view.safeAreaLayoutGuide).offset(-24)
			$0.width.lessThanOrEqualTo(UIDevice.current.isIpad ? 480 : 350)
		}

		topSpacer.snp.makeConstraints { make in
			make.height.equalTo(bottomSpacer.snp.height)
		}
		containerController = ContainerController(hostVC: self, containerView: containerView)
	}

	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	func setContent(_ content: UIViewController, completion: (() -> Void)? = nil) {
		// should not be animated for self sizing containers.
		containerController?.transition(content, animated: false, completion: completion)
	}

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		coordinator.animate(alongsideTransition: { [weak self] _ in
			self?.view.layoutIfNeeded()
		})
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {

	}
}
