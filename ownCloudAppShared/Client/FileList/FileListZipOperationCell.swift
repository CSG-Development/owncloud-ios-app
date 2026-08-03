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
	private var actionsTopToHeaderConstraint: Constraint?
	private var actionsTopToCardConstraint: Constraint?
	private var headerHeightConstraint: Constraint?
	private var cardTopConstraint: Constraint?
	private var cardBottomConstraint: Constraint?
	private var cardLeadingConstraint: Constraint?
	private var cardTrailingConstraint: Constraint?
	private var showsCardChrome = true

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
			cardTopConstraint = $0.top.equalToSuperview().offset(8).constraint
			cardBottomConstraint = $0.bottom.equalToSuperview().offset(-8).constraint
			cardLeadingConstraint = $0.leading.equalToSuperview().offset(16).constraint
			cardTrailingConstraint = $0.trailing.equalToSuperview().offset(-16).constraint
		}

		headerView.snp.makeConstraints {
			$0.top.leading.trailing.equalToSuperview()
			headerHeightConstraint = $0.height.equalTo(FileListActivityHeaderView.preferredHeight()).constraint
		}

		actionsView.snp.makeConstraints {
			actionsTopToHeaderConstraint = $0.top.equalTo(headerView.snp.bottom).constraint
			actionsTopToCardConstraint = $0.top.equalToSuperview().constraint
			actionsTopToCardConstraint?.deactivate()
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

		let showsCollapsibleHeader = records.count > 1
		showsCardChrome = showsCollapsibleHeader

		headerView.isHidden = !showsCollapsibleHeader
		headerView.isUserInteractionEnabled = showsCollapsibleHeader
		headerHeightConstraint?.update(offset: showsCollapsibleHeader ? FileListActivityHeaderView.preferredHeight() : 0)
		if showsCollapsibleHeader {
			actionsTopToCardConstraint?.deactivate()
			actionsTopToHeaderConstraint?.activate()
		} else {
			actionsTopToHeaderConstraint?.deactivate()
			actionsTopToCardConstraint?.activate()
		}

		if showsCollapsibleHeader {
			let combined = records.isEmpty ? Float(0) : Float(records.map(\.fractionCompleted).reduce(0, +) / Double(records.count))
			headerView.configure(
				operationCount: records.count,
				combinedProgress: combined,
				expanded: expanded,
				animated: animated
			)
			actionsView.configure(records: records, expanded: expanded, animated: animated)
		} else if let record = records.first {
			actionsView.configureSingle(record, animated: animated)
		} else {
			actionsView.configure(records: [], expanded: false, animated: false)
		}

		// Always use the app theme (not traitCollection) — ownCloud dark mode can diverge from system style at launch.
		applyThemeColors(isDark: Theme.shared.activeCollection.isDark)
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		applyThemeColors(isDark: collection.isDark)
	}

	private func applyThemeColors(isDark: Bool) {
		applyCardChromeAppearance(isDark: isDark)
		headerView.applyColors(isDark: isDark)
		actionsView.applyColors(isDark: isDark)
	}

	private func applyCardChromeAppearance(isDark: Bool) {
		if showsCardChrome {
			cardView.backgroundColor = HCColor.Structure.cardBackground(isDark)
			cardView.layer.borderWidth = 1
			cardView.layer.borderColor = HCColor.Content.border2(isDark).cgColor
			cardView.layer.cornerRadius = 12
			cardView.clipsToBounds = true
			cardTopConstraint?.update(offset: 8)
			cardBottomConstraint?.update(offset: -8)
			cardLeadingConstraint?.update(offset: 16)
			cardTrailingConstraint?.update(offset: -16)
		} else {
			// Single activity: same row layout; 16pt gaps come from top inset + row horizontalInset.
			cardView.backgroundColor = .clear
			cardView.layer.borderWidth = 0
			cardView.layer.borderColor = UIColor.clear.cgColor
			cardView.layer.cornerRadius = 0
			cardView.clipsToBounds = false
			cardTopConstraint?.update(offset: 16)
			cardBottomConstraint?.update(offset: 0)
			cardLeadingConstraint?.update(offset: 0)
			cardTrailingConstraint?.update(offset: 0)
		}
	}

	static func preferredHeight(expanded: Bool, operationCount: Int) -> CGFloat {
		if operationCount == 1 {
			// 16pt top gap + row; bottom flush with list content.
			return 16 + FileListActivityActionRowView.preferredHeight
		}
		let outerPadding: CGFloat = 16
		return outerPadding
			+ FileListActivityHeaderView.preferredHeight()
			+ FileListActivityActionsView.preferredHeight(expanded: expanded, operationCount: operationCount)
	}
}
