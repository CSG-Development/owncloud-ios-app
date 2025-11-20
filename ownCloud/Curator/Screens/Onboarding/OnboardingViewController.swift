import UIKit
import SnapKit
import ownCloudAppShared

class OnboardingViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
	private let pages: [OnboardingPage] = [
		.init(
			imageName: "onboarding/step_1",
			title: HCL10n.Onboarding.Step_ManageFiles.title,
			subtitle: HCL10n.Onboarding.Step_ManageFiles.subtitle
		),
		.init(
			imageName: "onboarding/step_1",
			title: HCL10n.Onboarding.Step_ShareFiles.title,
			subtitle: HCL10n.Onboarding.Step_ShareFiles.subtitle
		),
		.init(
			imageName: "onboarding/step_1",
			title: HCL10n.Onboarding.Step_MultiAccount.title,
			subtitle: HCL10n.Onboarding.Step_MultiAccount.subtitle
		),
		.init(
			imageName: "onboarding/step_1",
			title: HCL10n.Onboarding.Step_CameraUploads.title,
			subtitle: HCL10n.Onboarding.Step_CameraUploads.subtitle
		),
		.init(
			imageName: "onboarding/step_1",
			title: HCL10n.Onboarding.Step_VideoStreaming.title,
			subtitle: HCL10n.Onboarding.Step_VideoStreaming.subtitle
		)
	]
	private var currentPage = 0
	private var seenPageIndices: Set<Int> = HCPreferences.shared.onboardingSeenPageIndices

	private lazy var imageView: UIImageView = {
		let imageView = UIImageView(image: UIImage(named: "onboarding/background"))
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

	private lazy var pageControl: UIPageControl = {
		let pageControl = UIPageControl()
		pageControl.numberOfPages = pages.count
		pageControl.currentPage = currentPage
		pageControl.currentPageIndicatorTintColor = .white
		pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.5)
		pageControl.isUserInteractionEnabled = false
		pageControl.setContentCompressionResistancePriority(.required, for: .horizontal)
		return pageControl
	}()

	private lazy var skipButton: UIButton = {
		let button = UIButton(type: .system)
		button.setTitleColor(.white, for: .normal)
		button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
		button.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		button.snp.makeConstraints { $0.width.greaterThanOrEqualTo(50) }
		return button
	}()

	private lazy var nextButton: UIButton = {
		let button = UIButton(type: .system)
		button.tintColor = .white
		button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
		button.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		button.snp.makeConstraints { $0.width.greaterThanOrEqualTo(50) }
		return button
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
	}

	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// Resume from the first unseen page if onboarding was interrupted
		currentPage = firstUnseenPageIndex()
		configureViews()
		updateButtons()
	}

	private func configureViews() {
		view.backgroundColor = .black

		view.addSubview(imageViewContainer)
		imageViewContainer.snp.makeConstraints { $0.edges.equalToSuperview() }

		imageViewContainer.addSubview(imageView)
		imageView.snp.makeConstraints {
			$0.leading.centerY.trailing.equalToSuperview()
			if let image = imageView.image, image.size.width > 0 {
				$0.height.equalTo(imageView.snp.width)
					.multipliedBy(image.size.height / image.size.width)
			}
		}

		view.addSubview(controlsStackView)
		controlsStackView.snp.makeConstraints {
			$0.bottom.equalTo(view.safeAreaLayoutGuide)
			$0.height.equalTo(68)
			$0.centerX.equalToSuperview()
			$0.leading.greaterThanOrEqualToSuperview().offset(24)
		}

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
			$0.bottom.equalTo(controlsStackView.snp.top)
		}

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
}
