import UIKit
import SnapKit
import ownCloudAppShared

class OnboardingViewController: UIViewController, Themeable, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
	private let pages: [OnboardingPage] = [
		.init(
			imageNameLight: "onboarding/step_1_light",
			imageNameDark: "onboarding/step_1_dark",
			title: HCL10n.Onboarding.Step_ManageFiles.title,
			subtitle: HCL10n.Onboarding.Step_ManageFiles.subtitle
		),
		.init(
			imageNameLight: "onboarding/step_2_light",
			imageNameDark: "onboarding/step_2_dark",
			installAppImageNameLight: "onboarding/install_app_light",
			installAppImageNameDark: "onboarding/install_app_dark",
			title: HCL10n.Onboarding.Step_SyncFiles.title,
			subtitle: HCL10n.Onboarding.Step_SyncFiles.subtitle
		),
		.init(
			imageNameLight: "onboarding/step_3_light",
			imageNameDark: "onboarding/step_3_dark",
			title: HCL10n.Onboarding.Step_FileDeduplication.title,
			subtitle: HCL10n.Onboarding.Step_FileDeduplication.subtitle
		),
		.init(
			imageNameLight: "onboarding/step_4_light",
			imageNameDark: "onboarding/step_4_dark",
			title: HCL10n.Onboarding.Step_Search.title,
			subtitle: HCL10n.Onboarding.Step_Search.subtitle
		),
		.init(
			imageNameLight: "onboarding/step_5_light",
			imageNameDark: "onboarding/step_5_dark",
			title: HCL10n.Onboarding.Step_SecureSharing.title,
			subtitle: HCL10n.Onboarding.Step_SecureSharing.subtitle
		)
	]
	private var currentPage = 0
	private var seenPageIndices: Set<Int> = HCPreferences.shared.onboardingSeenPageIndices

	private lazy var imageView: UIImageView = {
		let imageView = UIImageView()
		imageView.contentMode = .scaleAspectFit
		imageView.clipsToBounds = true
		return imageView
	}()

	private lazy var imageViewContainer: UIView = {
		let view = UIView()
		view.clipsToBounds = true
		return view
	}()

	private let pageVC = UIPageViewController(
		transitionStyle: .scroll,
		navigationOrientation: .horizontal
	)

	private lazy var controlsGradientLayer: CAGradientLayer = {
		CAGradientLayer()
	}()

	private lazy var pageControl: UIPageControl = {
		let pageControl = UIPageControl()
		pageControl.numberOfPages = pages.count
		pageControl.currentPage = currentPage
		pageControl.isUserInteractionEnabled = false
		pageControl.setContentCompressionResistancePriority(.required, for: .horizontal)
		return pageControl
	}()

	private lazy var skipButton: UIButton = {
		let button = UIButton(type: .system)
		button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
		button.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		button.snp.makeConstraints { $0.width.greaterThanOrEqualTo(50) }
		return button
	}()

	private lazy var nextButton: UIButton = {
		let button = UIButton(type: .system)
		button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
		button.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		button.snp.makeConstraints { $0.width.greaterThanOrEqualTo(50) }
		return button
	}()

	private lazy var controlsStackViewContainer: UIView = {
		let view = UIView()
		view.backgroundColor = .clear
		return view
	}()

	private lazy var controlsStackView: UIStackView = {
		let stackView = UIStackView()
		stackView.axis = .horizontal
		stackView.backgroundColor = .clear
		stackView.spacing = 0
		stackView.distribution = .fill
		return stackView
	}()

	var onFinishedOnboarding: (() -> Void)?

	init() {
		super.init(nibName: nil, bundle: nil)
		Theme.shared.register(client: self, applyImmediately: true)
	}

	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	deinit {
		Theme.shared.unregister(client: self)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// Resume from the first unseen page if onboarding was interrupted
		currentPage = firstUnseenPageIndex()
		configureViews()
		updateButtons()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		controlsGradientLayer.frame = controlsStackViewContainer.bounds
	}

	private func configureViews() {
		// PageViewController
		addChild(pageVC)
		view.addSubview(pageVC.view)
		pageVC.didMove(toParent: self)
		pageVC.dataSource = self
		pageVC.delegate = self
		setPage(index: currentPage, animated: false)
		pageVC.view.snp.makeConstraints {
			$0.top.equalTo(view.safeAreaLayoutGuide)
			$0.leading.trailing.equalToSuperview()
			$0.bottom.equalTo(view.safeAreaLayoutGuide)
		}

		view.addSubview(controlsStackViewContainer)
		controlsStackViewContainer.snp.makeConstraints {
			$0.bottom.equalTo(view.safeAreaLayoutGuide)
			$0.height.equalTo(68)
			$0.leading.trailing.equalToSuperview()
		}
		controlsStackViewContainer.layer.insertSublayer(controlsGradientLayer, at: 0)

		controlsStackViewContainer.addSubview(controlsStackView)
		controlsStackView.snp.makeConstraints {
			$0.bottom.top.equalToSuperview()
			$0.centerX.equalToSuperview()
			$0.leading.greaterThanOrEqualToSuperview().offset(24)
		}
		controlsStackView.backgroundColor = .clear

		let spacer1 = HCSpacerView(nil, .horizontal)
		let spacer2 = HCSpacerView(nil, .horizontal)

		controlsStackView.addArrangedSubviews([
			skipButton,
			spacer1,
			pageControl,
			spacer2,
			nextButton
		])

		spacer1.snp.makeConstraints {
			$0.width.lessThanOrEqualTo(30)
			$0.width.equalTo(30).priority(.low)
			$0.width.equalTo(spacer2.snp.width)
		}
	}

	private func setPage(index: Int, animated: Bool) {
		let vc = OnboardingPageViewController(page: pages[index])
		let direction: UIPageViewController.NavigationDirection = (index >= currentPage) ? .forward : .reverse
		pageVC.setViewControllers([vc], direction: direction, animated: animated, completion: nil)
		currentPage = index
		pageControl.currentPage = index
		updateButtons()

		// Persist progress whenever a page is explicitly set
		markPageSeen(index: index)
	}

	private func updateButtons() {
		let isLast = currentPage == pages.count - 1
		nextButton.setImage(isLast ? nil : UIImage(named: "arrow-forward"), for: .normal)
		nextButton.setTitle(isLast ? HCL10n.Onboarding.doneButtonTitle : nil, for: .normal)
		skipButton.setTitle(isLast ? nil : HCL10n.Onboarding.skipButtonTitle, for: .normal)
	}

	@objc private func skipTapped() {
		completeOnboarding()
		onFinishedOnboarding?()
	}

	@objc private func nextTapped() {
		if currentPage < pages.count - 1 {
			setPage(index: currentPage + 1, animated: true)
		} else {
			completeOnboarding()
			onFinishedOnboarding?()
		}
	}

	// MARK: - UIPageViewControllerDataSource & Delegate

	func pageViewController(
		_ pageViewController: UIPageViewController,
		viewControllerBefore viewController: UIViewController
	) -> UIViewController? {
		guard currentPage > 0 else { return nil }

		return OnboardingPageViewController(page: pages[currentPage - 1])
	}

	func pageViewController(
		_ pageViewController: UIPageViewController,
		viewControllerAfter viewController: UIViewController
	) -> UIViewController? {
		guard currentPage < pages.count - 1 else { return nil }

		return OnboardingPageViewController(page: pages[currentPage + 1])
	}

	func pageViewController(
		_ pageViewController: UIPageViewController,
		didFinishAnimating finished: Bool,
		previousViewControllers: [UIViewController],
		transitionCompleted completed: Bool
	) {
		guard
			completed,
			let currentVC = pageVC.viewControllers?.first as? OnboardingPageViewController,
			let index = pages.firstIndex(of: currentVC.page)
		else { return }

		currentPage = index
		pageControl.currentPage = index
		updateButtons()

		// Persist progress when the user swipes between pages
		markPageSeen(index: index)
	}

	// MARK: - Progress persistence
	private func markPageSeen(index: Int) {
		if seenPageIndices.contains(index) == false {
			seenPageIndices.insert(index)
			HCPreferences.shared.onboardingSeenPageIndices = seenPageIndices
			checkIfCompleted()
		}
	}

	private func checkIfCompleted() {
		if seenPageIndices.count >= pages.count {
			HCPreferences.shared.shouldShowOnboarding = false
		}
	}

	private func completeOnboarding() {
		HCPreferences.shared.shouldShowOnboarding = false
	}

	private func firstUnseenPageIndex() -> Int {
		for index in 0..<pages.count {
			if seenPageIndices.contains(index) == false {
				return index
			}
		}
		return 0
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		let backgroundColor = collection.css.getColor(.fill, selectors: [.hcCardView, .background], for: nil)
		view.backgroundColor = backgroundColor

		let textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white

		pageControl.currentPageIndicatorTintColor = textColor
		pageControl.pageIndicatorTintColor = textColor.withAlphaComponent(0.435)
		skipButton.tintColor = textColor
		nextButton.tintColor = textColor

		let topColor = (backgroundColor ?? .clear).withAlphaComponent(0)
		let bottomColor = backgroundColor ?? .clear

		controlsGradientLayer.colors = [topColor.cgColor, bottomColor.cgColor]
		controlsGradientLayer.locations = [0.0, 0.33, 1.0]
		controlsGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
		controlsGradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
	}
}
