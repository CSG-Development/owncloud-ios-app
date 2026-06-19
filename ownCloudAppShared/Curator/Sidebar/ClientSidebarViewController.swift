import UIKit
import ownCloudSDK
import ownCloudApp

extension ThemeCSSSelector {
	static let logo = ThemeCSSSelector(rawValue: "logo")
}

public final class SidebarScrollView: UIScrollView {
	public override func touchesShouldCancel(in view: UIView) -> Bool {
		view is HCSidebarMenuRowView || super.touchesShouldCancel(in: view)
	}
}

// MARK: -

/// A thin view controller shim. It owns the layout, wires `SidebarDataModel` callbacks,
/// and exposes the public API consumed by the host app. All menu rendering is in
/// `+MenuRendering` and all folder animation logic is in `+FolderAnimation`.
public class ClientSidebarViewController: UIViewController, Themeable, ThemeCSSAutoSelector {

	public typealias ViewControllerNavigationPusher = (_ sidebar: ClientSidebarViewController, _ viewController: UIViewController, _ animated: Bool) -> Void

	// MARK: - Context

	public let originalContext: ClientContext
	public let sidebarContext: ClientContext
	public var clientContext: ClientContext { sidebarContext }
	public var navigationPusher: ViewControllerNavigationPusher?
	public var controllerConfiguration: AccountController.Configuration

	// MARK: - Views

	public var headerView = HCSidebarHeaderView(frame: .zero)
	let scrollView = SidebarScrollView()
	let contentStackView = UIStackView()
	let footerView = HCSidebarFooterView(frame: .zero)
	let footerViewDouble = HCSidebarFooterView(frame: .zero)
	private let backgroundPatchView = UIView()
	private var contentSizeObservation: NSKeyValueObservation?

	// MARK: - Callbacks

	public var onSettingsTap: (() -> Void)?
	public var onSignoutTap: (() -> Void)?
	public var onEditTap: (() -> Void)?

	// MARK: - Data model

	/// The SDK connectivity layer. All account/subscription lifecycle lives here.
	var dataModel: SidebarDataModel!

	// MARK: - Menu state (read/written by +MenuRendering and +FolderAnimation)

	var expandedFolderRefs: [OCDataItemReference] = []
	var highlightedItemRefs: [OCDataItemReference] = []
	var rowViewsByItemRef: [OCDataItemReference: HCSidebarMenuRowView] = [:]
	var rowContainersByItemRef: [OCDataItemReference: UIView] = [:]

	// MARK: - Animation constants (shared by +MenuRendering and +FolderAnimation)

	enum MenuAnimation {
		static let expandDuration: TimeInterval = 0.25
		static let collapseDuration: TimeInterval = 0.2
		static let horizontalInset: CGFloat = 16
	}

	// MARK: - Focus

	@objc public dynamic var focusedBookmark: OCBookmark? {
		didSet {
			Log.debug("New focusedBookmark: \(focusedBookmark?.displayName ?? "-")")
			dataModel?.updateAvailableSpace(focusedBookmark: focusedBookmark)
		}
	}

	private var focusedBookmarkNavigationRevocationAction: NavigationRevocationAction?

	// MARK: - Footer visibility

	private var shouldShowDouble = false {
		didSet {
			guard oldValue != shouldShowDouble else { return }
			updateFooter()
		}
	}

	// MARK: - Init

	public init(context inContext: ClientContext, controllerConfiguration: AccountController.Configuration) {
		self.controllerConfiguration = controllerConfiguration
		originalContext = inContext

		sidebarContext = ClientContext(with: originalContext)
		sidebarContext.postInitializationModifier = { (owner, context) in
			context.viewControllerPusher = owner as? ViewControllerPusher
			context.navigationRevocationHandler = owner as? NavigationRevocationHandler
		}

		super.init(nibName: nil, bundle: nil)

		sidebarContext.postInitialize(owner: self)

		navigationPusher = { sideBarViewController, viewController, _ in
			if let contentNavigationController = inContext.navigationController {
				contentNavigationController.setViewControllers([viewController], animated: false)
				sideBarViewController.splitViewController?.showDetailViewController(contentNavigationController, sender: sideBarViewController)
			}
		}
	}

	required public init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	deinit {
		Theme.shared.unregister(client: self)
	}

	// MARK: - Lifecycle

	public override func viewDidLoad() {
		super.viewDidLoad()

		configureLayout()
		configureDataModel()

		navigationItem.largeTitleDisplayMode = .never
		navigationItem.titleView = ClientSidebarViewController.buildNavigationLogoView()

		Theme.shared.register(client: self, applyImmediately: true)
		updateFooter()
		reloadMenu(animated: false)
	}

	public override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		updateShouldShowDouble()
		dataModel?.updateAvailableSpace(focusedBookmark: focusedBookmark)
	}

	// MARK: - Layout

	private func configureLayout() {
		view.addSubview(headerView)
		view.addSubview(scrollView)
		view.addSubview(footerView)
		view.addSubview(backgroundPatchView)

		scrollView.addSubview(contentStackView)
		scrollView.delegate = self
		scrollView.alwaysBounceVertical = true
		scrollView.delaysContentTouches = true
		scrollView.canCancelContentTouches = true
		scrollView.contentInset.top = 10

		footerView.isUserInteractionEnabled = false
		backgroundPatchView.isUserInteractionEnabled = false

		contentStackView.axis = .vertical
		contentStackView.spacing = 4
		contentStackView.alignment = .fill

		headerView.snp.makeConstraints {
			$0.top.equalToSuperview()
			$0.leading.trailing.equalTo(view.safeAreaLayoutGuide)
		}
		scrollView.snp.makeConstraints {
			$0.top.equalTo(headerView.snp.bottom)
			$0.leading.trailing.equalTo(view.safeAreaLayoutGuide)
			$0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
		}
		contentStackView.snp.makeConstraints {
			$0.edges.equalTo(scrollView.contentLayoutGuide)
			$0.width.equalTo(scrollView.frameLayoutGuide)
		}
		footerView.snp.makeConstraints {
			$0.leading.equalToSuperview().offset(MenuAnimation.horizontalInset)
			$0.trailing.equalToSuperview().offset(-MenuAnimation.horizontalInset)
			$0.bottom.equalToSuperview().offset(-12)
		}
		backgroundPatchView.snp.makeConstraints {
			$0.leading.trailing.equalTo(view.safeAreaLayoutGuide)
			$0.top.equalTo(view.keyboardLayoutGuide)
			$0.bottom.equalToSuperview()
		}

		contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
			self?.updateShouldShowDouble()
		}
	}

	// MARK: - Data model setup

	private func configureDataModel() {
		dataModel = SidebarDataModel(
			clientContext: clientContext,
			controllerConfiguration: controllerConfiguration
		)

		dataModel.onMenuNeedsReload = { [weak self] in
			self?.reloadMenu(animated: false)
		}

		dataModel.onBookmarkChanged = { [weak self] bookmark in
			self?.headerView.bookmark = bookmark
			self?.headerView.onEditTap = self?.onEditTap
		}

		dataModel.onSpaceUpdated = { [weak self] used, remaining in
			self?.footerView.bytesUsed = used
			self?.footerView.bytesRemaining = remaining
			self?.footerViewDouble.bytesUsed = used
			self?.footerViewDouble.bytesRemaining = remaining
		}

		dataModel.onConnectionClosed = { [weak self] in
			self?.footerView.bytesUsed = nil
			self?.footerView.bytesRemaining = nil
			self?.footerViewDouble.bytesUsed = nil
			self?.footerViewDouble.bytesRemaining = nil
		}
	}

	// MARK: - Public API

	public func forceReloadBookmarks() {
		dataModel.forceReloadBookmarks()
	}

	public func updateAvailableSpace() {
		dataModel.updateAvailableSpace(focusedBookmark: focusedBookmark)
	}

	public func accountController(for bookmarkUUID: UUID) -> AccountController? {
		dataModel.accountController(for: bookmarkUUID)
	}

	public func section(for bookmarkUUID: UUID) -> AccountControllerSection? {
		dataModel.accountController(for: bookmarkUUID).map { AccountControllerSection(with: $0) }
	}

	public var allSections: [AccountControllerSection] {
		dataModel.accountControllers.map { AccountControllerSection(with: $0) }
	}

	public var sectionOfCurrentSelection: AccountControllerSection? {
		if let bookmarkUUID = focusedBookmark?.uuid {
			return section(for: bookmarkUUID)
		}
		return allSections.first
	}

	func registerFocusedBookmarkRevocation(for bookmark: OCBookmark?) {
		guard let bookmarkUUID = bookmark?.uuid else { return }
		focusedBookmarkNavigationRevocationAction = NavigationRevocationAction(
			triggeredBy: [.connectionClosed(bookmarkUUID: bookmarkUUID)],
			action: { [weak self] _, _ in
				if self?.focusedBookmark?.uuid == bookmarkUUID {
					self?.focusedBookmark = nil
				}
			}
		)
		focusedBookmarkNavigationRevocationAction?.register(globally: true)
	}

	// MARK: - Theme

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		let bg = collection.css.getColor(.fill, selectors: [.sidebar, .collection], for: view)
		view.backgroundColor = bg
		scrollView.backgroundColor = bg
		contentStackView.backgroundColor = bg
		backgroundPatchView.backgroundColor = bg
	}

	public var cssAutoSelectors: [ThemeCSSSelector] { [.sidebar, .collection] }

	// MARK: - Footer

	func updateShouldShowDouble() {
		shouldShowDouble = scrollView.bounds.size.height < scrollView.contentSize.height
	}

	private func updateFooter() {
		UIView.animate(withDuration: 0.3) {
			self.footerView.alpha = self.shouldShowDouble ? 0 : 1
			self.footerViewDouble.alpha = 1 - self.footerView.alpha
			var insets = self.scrollView.contentInset
			insets.bottom = self.shouldShowDouble ? 12 : 0
			self.scrollView.contentInset = insets
		}
	}
}

// MARK: - Branding

extension ClientSidebarViewController {
	static public func buildNavigationLogoView() -> ThemeCSSView {
		HCNavigationLogoView(frame: .zero)
	}
}

// MARK: - UIScrollViewDelegate

extension ClientSidebarViewController: UIScrollViewDelegate {
	public func scrollViewDidScroll(_ scrollView: UIScrollView) {
		updateShouldShowDouble()
	}
}

// MARK: - ViewControllerPusher

extension ClientSidebarViewController: ViewControllerPusher {
	public func pushViewController(context: ClientContext?, provider: (ClientContext) -> UIViewController?, push: Bool, animated: Bool) -> UIViewController? {
		var effectiveContext: ClientContext? = context

		if effectiveContext == sidebarContext {
			effectiveContext = originalContext
		} else if effectiveContext?.viewControllerPusher === self {
			effectiveContext = ClientContext(with: context, modifier: { context in
				context.viewControllerPusher = nil
			})
		}

		if let effectiveContext, let viewController = provider(effectiveContext) {
			if push {
				if let navigationPusher {
					navigationPusher(self, viewController, animated)
				} else if let navigationController = effectiveContext.navigationController {
					navigationController.pushViewController(viewController, animated: animated)
				}
			}
			return viewController
		}

		return nil
	}
}

// MARK: - NavigationRevocationHandler

extension ClientSidebarViewController: NavigationRevocationHandler {
	public func handleRevocation(event: NavigationRevocationEvent, context: ClientContext?, for viewController: UIViewController) {
		if let history = sidebarContext.browserController?.history {
			var hasHistoryItem = false
			while let historyItem = history.item(for: viewController) {
				history.remove(item: historyItem, completion: nil)
				hasHistoryItem = true
			}
			if !hasHistoryItem, viewController.presentingViewController != nil {
				dismissDeep(viewController: viewController)
			}
		}
	}

	private func dismissDeep(viewController: UIViewController) {
		guard viewController.presentingViewController != nil else { return }
		var start: UIViewController? = viewController
		while let deeper = start?.presentedViewController { start = deeper }
		start?.dismiss(animated: true) { [weak self] in
			self?.dismissDeep(viewController: viewController)
		}
	}
}
