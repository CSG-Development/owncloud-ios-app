import ownCloudSDK
import Combine
import UIKit
import Reusable
import SnapKit

private struct RowRenderState: Equatable {
	let title: String
	let isLoading: Bool
	let isExpanded: Bool
	let isExpandable: Bool
	let depth: Int

	init(_ item: LocationTreeItem) {
		self.title = item.title
		self.isLoading = item.isLoading
		self.isExpanded = item.isExpanded
		self.isExpandable = item.isExpandable
		self.depth = item.depth
	}
}

final class LocationTreeViewController: UIViewController, UITableViewDelegate {
	enum Section { case main }

	let viewModel: LocationTreeViewModel
	let clientContext: ClientContext

	private var initialSnapshotApplied = false
	private var renderCache: [OCPath: RowRenderState] = [:]

	private lazy var tableView: UITableView = {
		let tableView = UITableView(frame: .zero, style: .plain)
		tableView.delegate = self
		tableView.register(cellType: LocationTreeCell.self)
		tableView.rowHeight = 52
		tableView.separatorStyle = .singleLine
		return tableView
	}()

	private var dataSource: UITableViewDiffableDataSource<Section, String>!
	private var disposeBag = Set<AnyCancellable>()

	private var itemsByID: [OCPath: LocationTreeItem] = [:]
	private var orderedIDs: [OCPath] = []

	init(viewModel: LocationTreeViewModel, clientContext: ClientContext) {
		self.viewModel = viewModel
		self.clientContext = clientContext

		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		setupTable()
		setupDataSource()
		bindViewModel()
	}

	private func setupTable() {
		view.addSubview(tableView)
		tableView.backgroundColor = .clear

		tableView.snp.makeConstraints {
			$0.top.equalTo(view.safeAreaLayoutGuide.snp.top)
			$0.leading.trailing.bottom.equalToSuperview()
		}
	}

	private func setupDataSource() {
		dataSource = UITableViewDiffableDataSource<Section, String>(tableView: tableView) { [weak self] tableView, indexPath, id in
			guard
				let self = self,
				let item = self.itemsByID[id as OCPath]
			else { return UITableViewCell() }
			let cell = tableView.dequeueReusableCell(for: indexPath) as LocationTreeCell

			cell.configure(with: item) { [weak self] in
				self?.didTapExpand(for: id as OCPath)
			}
			// Also allow tapping the whole row
			cell.contentView.gestureRecognizers?.forEach { cell.contentView.removeGestureRecognizer($0) }
			let tap = UITapGestureRecognizer(target: self, action: #selector(LocationTreeViewController.handleRowTap(_:)))
			tap.name = id as String
			cell.contentView.addGestureRecognizer(tap)
			return cell
		}
	}

	private func bindViewModel() {
		viewModel.$items
			.receive(on: DispatchQueue.main)
			.sink { [weak self] items in
				guard let self else { return }

				// 1) Keep local caches
				self.itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
				self.orderedIDs = items.map(\.id)

				// 2) Compute which rows truly changed content
				var reconfigureIDs: [OCPath] = []
				reconfigureIDs.reserveCapacity(items.count)
				for item in items {
					let newState = RowRenderState(item)
					if self.renderCache[item.id] != newState {
						reconfigureIDs.append(item.id)
						self.renderCache[item.id] = newState
					}
				}

				// 3) Build a fresh snapshot with identities in order
				var snap = NSDiffableDataSourceSnapshot<Section, String>()
				snap.appendSections([.main])
				snap.appendItems(self.orderedIDs.map { $0 as String }, toSection: .main)

				// 4) Reload changed rows to force cell.configure to run (safer than reconfigure for custom cells)
				if !reconfigureIDs.isEmpty { snap.reconfigureItems(reconfigureIDs.map { $0 as String }) }

				// 5) Apply with reasonable animations
				if !self.initialSnapshotApplied {
					self.initialSnapshotApplied = true
					self.dataSource.apply(snap, animatingDifferences: false) // first paint: no animation
				} else {
					self.dataSource.apply(snap, animatingDifferences: false)
				}
				self.view.setNeedsLayout()
			}
			.store(in: &disposeBag)
	}

	// MARK: - Expand button action
	private func didTapExpand(for id: OCPath) {
		viewModel.toggleExpand(id: id)
	}

	@objc private func handleRowTap(_ gr: UITapGestureRecognizer) {
		guard let name = gr.name else { return }
		let id: OCPath = (name as NSString) as OCPath
		// Dismiss popover and open folder
		let loc = OCLocation(driveID: nil, path: id as String)
		self.presentingViewController?.dismiss(animated: true, completion: { [weak self] in
			guard let self else { return }
			_ = loc.openItem(from: self.clientContext.rootViewController, with: self.clientContext, animated: true, pushViewController: true, completion: nil)
		})
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		// Dynamically size popover: width = 70% screen, height = min(content, 50% screen)
		let screenBounds = UIScreen.main.bounds
		let targetWidth = max(280, floor(screenBounds.width * 0.7))
		// Force layout to get accurate content size
		tableView.layoutIfNeeded()
		let contentHeight = tableView.contentSize.height
		let maxHeight = floor(screenBounds.height * 0.5)
		let targetHeight = min(maxHeight, max(44, contentHeight))
		preferredContentSize = CGSize(width: targetWidth, height: targetHeight)
	}
}
