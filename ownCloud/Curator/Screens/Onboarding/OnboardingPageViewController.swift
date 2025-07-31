import UIKit
import SnapKit
import ownCloudAppShared

class OnboardingPageViewController: UIViewController {
	let page: OnboardingPage

	private lazy var pageContentView: OnboardingContentView = {
		OnboardingContentView(page)
	}()

	private let scrollView = UIScrollView()
	private let scrollContentView = UIView()

	init(page: OnboardingPage) {
		self.page = page

		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		view.clipsToBounds = true
		view.addSubview(scrollView)
		scrollView.snp.makeConstraints { $0.edges.equalToSuperview() }

		scrollView.addSubview(scrollContentView)
		scrollContentView.snp.makeConstraints {
			$0.edges.equalToSuperview()
			$0.width.equalTo(view)

			if UIDevice.current.userInterfaceIdiom == .pad {
				$0.height.equalTo(view)
			}
		}

		scrollContentView.addSubview(pageContentView)
		pageContentView.snp.makeConstraints {
			$0.centerX.equalToSuperview()
			$0.leading.greaterThanOrEqualToSuperview().offset(24)

			if UIDevice.current.userInterfaceIdiom == .pad {
				$0.centerY.equalToSuperview()
			} else {
				$0.top.equalToSuperview().offset(24)
				$0.bottom.equalToSuperview().priority(.low)
			}
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		updateLandscapePhoneConstraint()
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)

		updateLandscapePhoneConstraint()
	}

	private func updateLandscapePhoneConstraint() {
		let isPhone = traitCollection.userInterfaceIdiom == .phone
		let isLandscape = traitCollection.verticalSizeClass == .compact

		pageContentView.useSmallerImage = isPhone && isLandscape
	}
}
