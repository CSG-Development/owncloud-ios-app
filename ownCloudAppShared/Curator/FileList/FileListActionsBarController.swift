import UIKit
import ownCloudSDK

/// Hosts the sideways multi-select / drop-target actions collection under the nav chrome.
final class FileListActionsBarController {
	static let preferredHeight: CGFloat = 72

	let containerView: UIView = {
		let container = UIView()
		container.translatesAutoresizingMaskIntoConstraints = false
		container.clipsToBounds = true
		container.isHidden = true
		return container
	}()

	private(set) var heightConstraint: NSLayoutConstraint?
	private weak var hostViewController: UIViewController?
	private weak var section: CollectionViewSection?
	private var childViewController: CollectionViewController? {
		willSet {
			if let childViewController {
				removeChild(childViewController)
			}
		}
		didSet {
			if let childViewController {
				addChild(childViewController)
			}
			updateVisibility()
		}
	}

	var isPresented: Bool {
		childViewController != nil
	}

	func install(in host: UIViewController) -> NSLayoutConstraint {
		hostViewController = host
		let height = containerView.heightAnchor.constraint(equalToConstant: 0)
		heightConstraint = height
		return height
	}

	func show(with datasource: OCDataSource, clientContext: ClientContext?) {
		guard childViewController == nil else { return }

		let itemSize = NSCollectionLayoutSize(widthDimension: .estimated(48), heightDimension: .fractionalHeight(1))
		let item = NSCollectionLayoutItem(layoutSize: itemSize)
		let actionSection = CollectionViewSection(
			identifier: "actions",
			dataSource: datasource,
			cellStyle: .init(with: .gridCell),
			cellLayout: .sideways(
				item: item,
				groupSize: itemSize,
				edgeSpacing: NSCollectionLayoutEdgeSpacing(leading: .fixed(10), top: .fixed(0), trailing: .fixed(10), bottom: .fixed(0)),
				contentInsets: NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0),
				orthogonalScrollingBehaviour: .continuous
			),
			clientContext: clientContext
		)
		actionSection.animateDifferences = false
		let actionsViewController = CollectionViewController(context: clientContext, sections: [actionSection])
		section = actionSection
		actionsViewController.view.translatesAutoresizingMaskIntoConstraints = false
		if let actionsCollectionView = actionsViewController.view as? UICollectionView {
			actionsCollectionView.showsVerticalScrollIndicator = false
			actionsCollectionView.alwaysBounceVertical = false
			actionsCollectionView.isScrollEnabled = false
		}
		childViewController = actionsViewController
	}

	func close() {
		section = nil
		childViewController = nil
	}

	func applyTheme(fillColor: UIColor?) {
		containerView.backgroundColor = fillColor
	}

	private func addChild(_ viewController: CollectionViewController) {
		guard let hostViewController else { return }
		hostViewController.addChild(viewController)
		containerView.addSubview(viewController.view)
		NSLayoutConstraint.activate([
			viewController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
			viewController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
			viewController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
			viewController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
			viewController.view.heightAnchor.constraint(equalToConstant: Self.preferredHeight)
		])
		viewController.didMove(toParent: hostViewController)
	}

	private func removeChild(_ viewController: CollectionViewController) {
		viewController.willMove(toParent: nil)
		viewController.view.removeFromSuperview()
		viewController.removeFromParent()
	}

	private func updateVisibility() {
		let show = childViewController != nil
		containerView.isHidden = !show
		heightConstraint?.constant = show ? Self.preferredHeight : 0
		UIView.animate(withDuration: 0.2) {
			self.hostViewController?.view.layoutIfNeeded()
		}
	}
}
