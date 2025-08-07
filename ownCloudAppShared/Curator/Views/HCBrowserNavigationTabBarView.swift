import UIKit
import SnapKit

public final class HCBrowserNavigationTabBarView: ThemeCSSView {
	public enum Tab: Int, CaseIterable {
		case files, search, status, offline

		var image: UIImage? {
			return switch self {
				case .files: UIImage(named: "tab_bar/folder", in: Bundle.sharedAppBundle, with: nil)
				case .search: UIImage(named: "tab_bar/link", in: Bundle.sharedAppBundle, with: nil)
				case .status: UIImage(named: "tab_bar/share", in: Bundle.sharedAppBundle, with: nil)
				case .offline: UIImage(named: "tab_bar/offline", in: Bundle.sharedAppBundle, with: nil)
			}
		}

		var selectedImage: UIImage? {
			return switch self {
				case .files: UIImage(named: "tab_bar/folder_filled", in: Bundle.sharedAppBundle, with: nil)
				case .search: UIImage(named: "tab_bar/link_filled", in: Bundle.sharedAppBundle, with: nil)
				case .status: UIImage(named: "tab_bar/share_filled", in: Bundle.sharedAppBundle, with: nil)
				case .offline: UIImage(named: "tab_bar/offline_filled", in: Bundle.sharedAppBundle, with: nil)
			}
		}

		var title: String {
			return switch self {
				case .files: HCL10n.TabBar.files
				case .search: HCL10n.TabBar.search
				case .status: HCL10n.TabBar.status
				case .offline: HCL10n.TabBar.offline
			}
		}
	}

	lazy var stackView: UIStackView = {
		let stackView = UIStackView()
		stackView.axis = .horizontal
		stackView.distribution = .fillEqually
		return stackView
	}()

	private var tabBarButtons: [UIButton] = []

	var onTabSelected: ((Tab?) -> Void)?

	override init() {
		super.init()

		self.cssSelector = .tabBar

		addSubview(stackView)
		stackView.snp.remakeConstraints {
			$0.top.bottom.centerX.equalToSuperview()
			$0.leading.greaterThanOrEqualTo(8)
			$0.width.lessThanOrEqualTo(800)
			$0.width.equalToSuperview().priority(.low)
		}
		stackView.setContentHuggingPriority(.defaultLow, for: .horizontal)

		reloadData()
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("Not implemented")
	}

	var selectedTab: Tab? {
		didSet {
			updateViews()
		}
	}

	func isTabSelected(_ tab: Tab) -> Bool {
		selectedTab != nil ? selectedTab == tab : false
	}

	private func reloadData() {
		stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
		tabBarButtons = []
		var buttons: [UIButton] = []
		for tab in Tab.allCases {
			let button = HCImageHighlightCapsuleButton(
				image: tab.image,
				selectedImage: tab.selectedImage,
				title: tab.title
			)
			button.tag = tab.rawValue
			button.addAction(
				UIAction { [weak self] action in
				guard let self, let sender = action.sender as? UIButton else { return }
					let updateTab: ( (Tab?) -> Void) = { [weak self] tab in
						guard let self else { return }

						self.selectedTab = tab
						onTabSelected?(tab)
					}

					let tappedTab = Tab(rawValue: sender.tag)!
					if let selectedTab = self.selectedTab {
						if tappedTab != selectedTab {
							updateTab(tappedTab)
						}
					} else {
						updateTab(tappedTab)
					}
				},
				for: .touchUpInside
			)
			buttons.append(button)
		}
		tabBarButtons = buttons
		stackView.addArrangedSubviews(buttons)
		updateViews()
	}

	private func updateViews() {
		for button in tabBarButtons {
			button.isSelected = selectedTab != nil ? selectedTab!.rawValue == button.tag : false
		}
	}
}
