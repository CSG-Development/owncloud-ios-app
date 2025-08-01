import UIKit
import SnapKit

public final class HCBrowserNavigationTabBarView: ThemeCSSView {
	public enum Tab: Int, CaseIterable {
		case files, links, uploads, offline

		var image: UIImage? {
			return switch self {
				case .files: UIImage(systemName: "star.fill")
				case .links: UIImage(systemName: "star.fill")
				case .uploads: UIImage(systemName: "star.fill")
				case .offline: UIImage(systemName: "star.fill")
			}
		}

		var title: String {
			return switch self {
				case .files: "Files"
				case .links: "Links"
				case .uploads: "Uploads"
				case .offline: "Offline"
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
		stackView.snp.remakeConstraints { $0.edges.equalToSuperview() }

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
			let button = ImageHighlightCapsuleButton(image: tab.image, title: tab.title)
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
