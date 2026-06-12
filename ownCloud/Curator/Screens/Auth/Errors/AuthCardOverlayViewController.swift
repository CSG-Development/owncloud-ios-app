import SnapKit
import UIKit
import ownCloudAppShared

/// Presents an auth error card centered over a dimmed overlay.
final class AuthCardOverlayViewController: UIViewController {
	private let contentViewController: UIViewController
	private let onOverlayTap: (() -> Void)?
	private var cardContainerView: UIView!
	private var containerStackView: UIStackView!

	private lazy var overlay: HCOverlayView = HCOverlayView()

	init(content: UIViewController, onOverlayTap: (() -> Void)? = nil) {
		self.contentViewController = content
		self.onOverlayTap = onOverlayTap
		super.init(nibName: nil, bundle: nil)
		modalPresentationStyle = .overFullScreen
		modalTransitionStyle = .crossDissolve
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .clear

		view.addSubview(overlay)
		overlay.snp.makeConstraints { $0.edges.equalToSuperview() }

		let stackView = UIStackView()
		stackView.axis = .vertical
		stackView.alignment = .center
		stackView.isLayoutMarginsRelativeArrangement = true
		stackView.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
		self.containerStackView = stackView
		view.addSubview(stackView)
		stackView.snp.makeConstraints {
			$0.top.equalTo(view.safeAreaLayoutGuide)
			$0.leading.trailing.equalToSuperview()
			$0.bottom.equalTo(view.safeAreaLayoutGuide)
		}

		let topSpacer = HCSpacerView(nil, .vertical)
		let bottomSpacer = HCSpacerView(nil, .vertical)
		topSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
		bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)

		let containerView = UIView()
		containerView.backgroundColor = .clear
		self.cardContainerView = containerView
		stackView.addArrangedSubviews([topSpacer, containerView, bottomSpacer])
		topSpacer.snp.makeConstraints { $0.height.equalTo(bottomSpacer.snp.height) }

		containerView.snp.makeConstraints {
			$0.leading.greaterThanOrEqualTo(view.safeAreaLayoutGuide).offset(24)
			$0.trailing.lessThanOrEqualTo(view.safeAreaLayoutGuide).offset(-24)
			$0.width.lessThanOrEqualTo(UIDevice.current.isIpad ? 480 : 350)
		}

		addChild(contentViewController)
		containerView.addSubview(contentViewController.view)
		contentViewController.view.snp.makeConstraints { $0.edges.equalToSuperview() }
		contentViewController.didMove(toParent: self)

		let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapOverlay))
		tapRecognizer.delegate = self
		stackView.addGestureRecognizer(tapRecognizer)
	}

	@objc private func didTapOverlay() {
		onOverlayTap?()
	}
}

extension AuthCardOverlayViewController: UIGestureRecognizerDelegate {
	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		let point = touch.location(in: containerStackView)
		return !(cardContainerView?.frame.contains(point) ?? false)
	}
}
