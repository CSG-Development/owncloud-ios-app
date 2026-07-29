import SnapKit
import UIKit

/// Expandable “Activity in progress” card listing in-flight zip (and future) file operations.
final class FileListZipOperationCell: UICollectionViewCell, Themeable {

	var onToggleExpanded: (() -> Void)? {
		didSet { headerView.onToggleExpanded = onToggleExpanded }
	}
	var onCancelRecord: ((ZipOperationRecord) -> Void)? {
		didSet { actionsView.onCancelRecord = onCancelRecord }
	}

	private let cardView = UIView()
	private let headerView = FileListActivityHeaderView()
	private let actionsView = FileListActivityActionsView()
	private var themeRegistered = false

	override init(frame: CGRect) {
		super.init(frame: frame)

		contentView.backgroundColor = .clear
		backgroundColor = .clear

		cardView.layer.cornerRadius = 12
		cardView.layer.borderWidth = 1
		cardView.clipsToBounds = true

		contentView.addSubview(cardView)
		cardView.addSubview(headerView)
		cardView.addSubview(actionsView)

		cardView.snp.makeConstraints {
			$0.top.bottom.equalToSuperview().inset(8)
			$0.leading.trailing.equalToSuperview().inset(16)
		}

		headerView.snp.makeConstraints {
			$0.top.leading.trailing.equalToSuperview()
			$0.height.equalTo(FileListActivityHeaderView.preferredHeight())
		}

		actionsView.snp.makeConstraints {
			$0.top.equalTo(headerView.snp.bottom)
			$0.leading.trailing.bottom.equalToSuperview()
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		if themeRegistered {
			Theme.shared.unregister(client: self)
		}
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil, !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func configure(records: [ZipOperationRecord], expanded: Bool, animated: Bool = false) {
		headerView.onToggleExpanded = onToggleExpanded
		actionsView.onCancelRecord = onCancelRecord

		let combined = records.isEmpty ? Float(0) : Float(records.map(\.fractionCompleted).reduce(0, +) / Double(records.count))
		headerView.configure(
			operationCount: records.count,
			combinedProgress: combined,
			expanded: expanded,
			animated: animated
		)
		actionsView.configure(records: records, expanded: expanded, animated: animated)
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		cardView.backgroundColor = HCColor.Structure.cardBackground(collection.isDark)
		cardView.layer.borderColor = HCColor.Content.border2(collection.isDark).cgColor
		headerView.applyColors(isDark: collection.isDark)
		actionsView.applyColors(isDark: collection.isDark)
	}

	static func preferredHeight(expanded: Bool, operationCount: Int) -> CGFloat {
		let outerPadding: CGFloat = 16
		return outerPadding
			+ FileListActivityHeaderView.preferredHeight()
			+ FileListActivityActionsView.preferredHeight(expanded: expanded, operationCount: operationCount)
	}
}
