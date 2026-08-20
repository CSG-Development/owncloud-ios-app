import UIKit
import ownCloudSDK

final class FileListItemCell: UICollectionViewCell, Themeable {

	enum Layout {
		case list
		case grid
		case gridLowDetail
		case gridNoDetail

		var isGrid: Bool {
			switch self {
			case .list: return false
			case .grid, .gridLowDetail, .gridNoDetail: return true
			}
		}
	}

	private static let listIconSize: CGFloat = 40
	private static let selectionIndicatorSize: CGFloat = 24
	private static let accessorySize: CGFloat = 32

	private let iconImageView = UIImageView()
	private let titleLabel = UILabel()
	private let detailLabel = UILabel()
	private let detailSegmentView = SegmentView(with: [], truncationMode: .truncateTail, limitVerticalSpaceUsage: true)
	private let selectionIndicator = FileListSelectionIndicator()
	private let moreButton = UIButton(type: .system)
	private let progressView = ProgressView()

	private var layoutConstraints: [NSLayoutConstraint] = []
	private var currentLayout: Layout = .list
	private var showsSelection = false
	private var showsMoreButton = false
	private var themeRegistered = false
	private var isDark = false
	private var iconRequest: OCResourceRequest?
	private var configuredItemKey: String?
	private var configuredSegmentsKey: String?
	private var configuredItem: OCItem?
	private weak var clientContext: ClientContext?
	private var observedLocalID: OCLocalID?
	private var progressObserver: NSObjectProtocol?
	private var activityObserver: NSObjectProtocol?

	override init(frame: CGRect) {
		super.init(frame: frame)

		iconImageView.translatesAutoresizingMaskIntoConstraints = false
		iconImageView.contentMode = .scaleAspectFit
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		detailLabel.translatesAutoresizingMaskIntoConstraints = false
		detailSegmentView.translatesAutoresizingMaskIntoConstraints = false
		selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
		moreButton.translatesAutoresizingMaskIntoConstraints = false
		progressView.translatesAutoresizingMaskIntoConstraints = false

		titleLabel.numberOfLines = 1
		titleLabel.lineBreakMode = .byTruncatingMiddle
		titleLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)

		detailLabel.numberOfLines = 1
		detailLabel.lineBreakMode = .byTruncatingTail
		detailLabel.font = UIFont.preferredFont(forTextStyle: .footnote)

		detailSegmentView.insets = .zero
		detailSegmentView.itemSpacing = 5
		detailSegmentView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		moreButton.setImage(UIImage(named: "more-dots")?.withRenderingMode(.alwaysTemplate), for: .normal)
		moreButton.contentMode = .center
		moreButton.isPointerInteractionEnabled = true
		moreButton.accessibilityLabel = OCLocalizedString("More", nil)
		moreButton.addTarget(self, action: #selector(moreButtonTapped), for: .primaryActionTriggered)
		moreButton.isHidden = true

		progressView.isHidden = true
		progressView.cssSelectors = [.accessory, .progress]
		isOpaque = false
		contentView.isOpaque = false
		backgroundColor = .clear
		contentView.backgroundColor = .clear

		contentView.addSubview(iconImageView)
		contentView.addSubview(titleLabel)
		contentView.addSubview(detailLabel)
		contentView.addSubview(detailSegmentView)
		contentView.addSubview(selectionIndicator)
		contentView.addSubview(moreButton)
		contentView.addSubview(progressView)

		NSLayoutConstraint.activate([
			moreButton.widthAnchor.constraint(equalToConstant: Self.accessorySize),
			moreButton.heightAnchor.constraint(equalToConstant: 42)
		])

		applyLayout(.list, showsSelection: false, showsAccessory: false)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		stopObservingProgress()
		if themeRegistered {
			Theme.shared.unregister(client: self)
		}
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		stopObservingProgress()
		cancelIconRequest(core: clientContext?.core)
		configuredItem = nil
		configuredItemKey = nil
		configuredSegmentsKey = nil
		clientContext = nil
		currentLayout = .list
		showsMoreButton = false
		progressView.progress = nil
		moreButton.isHidden = true
		progressView.isHidden = true
		detailSegmentView.items = []
		detailSegmentView.isHidden = true
		detailLabel.isHidden = true
		showsSelection = false
		selectionIndicator.isHidden = true
		selectionIndicator.isSelected = false
		contentView.backgroundColor = .clear
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil, !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func configure(
		item: OCItem,
		core: OCCore?,
		clientContext: ClientContext?,
		layout: Layout,
		showsSelection: Bool,
		isSelected: Bool
	) {
		guard Thread.isMainThread else {
			OnMainThread(inline: true) { [weak self] in
				self?.configure(
					item: item,
					core: core,
					clientContext: clientContext,
					layout: layout,
					showsSelection: showsSelection,
					isSelected: isSelected
				)
			}
			return
		}

		self.clientContext = clientContext

		let itemKey = item.localID ?? item.fileID ?? item.path ?? item.name ?? ""
		let statusKey = item.fileListStatusKey(core: core)
		let syncKey = "\(item.syncActivity.rawValue)"
		let itemConfigurationKey = "\(itemKey)|\(layout)|\(showsSelection)|\(isSelected)|\(item.sizeLocalized)|\(item.lastModifiedLocalizedCompact)|\(syncKey)|\(statusKey)"
		let shouldReloadIcon = itemConfigurationKey != configuredItemKey
		configuredItemKey = itemConfigurationKey

		configuredItem = item
		titleLabel.text = item.name ?? ""
		detailLabel.text = item.fileListDetailText
		titleLabel.isHidden = layout == .gridNoDetail
		let showsListDetail = layout == .list
		let showsGridDetail = layout == .grid
		detailLabel.isHidden = !showsGridDetail
		detailSegmentView.isHidden = !showsListDetail
		moreButton.accessibilityLabel = OCLocalizedFormat("More for {{title}}", ["title": item.name ?? ""])

		updateDetailSegmentsIfNeeded(for: item, core: core)
		updateAccessoryAndProgress(for: item, layout: layout, showsSelection: showsSelection, isSelected: isSelected, forceLayout: true)

		loadIcon(for: item, core: core, layout: layout, reloadPlaceholder: shouldReloadIcon)
		startObservingProgress(for: item)
		updateAccessibility(layout: layout, showsListDetail: showsListDetail)
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		isDark = collection.isDark
		titleLabel.textColor = HCColor.Content.textPrimary(collection.isDark)
		detailLabel.textColor = HCColor.Content.textSecondary(collection.isDark)
		moreButton.tintColor = HCColor.Interaction.buttonsPrimarySolidOutlined(collection.isDark)
		contentView.backgroundColor = .clear
		backgroundColor = .clear
		isOpaque = false
		contentView.isOpaque = false
		updateSelectionAppearance(isSelected: selectionIndicator.isSelected)
		if event != .initial, let item = configuredItem {
			iconImageView.image = item.fileListIconImage(fitIn: iconSize(for: currentLayout))
		}
	}

	@objc private func moreButtonTapped() {
		guard let item = configuredItem, let clientContext else { return }
		clientContext.moreItemHandler?.moreOptions(for: item, at: .moreItem, context: clientContext, sender: moreButton)
	}

	private func iconSize(for layout: Layout) -> CGSize {
		layout.isGrid
			? CGSize(width: 120, height: 120)
			: CGSize(width: Self.listIconSize, height: Self.listIconSize)
	}

	private func updateSelectionAppearance(isSelected: Bool) {
		if showsSelection, isSelected {
			contentView.backgroundColor = HCColor.Interaction.secondaryTransparentPressed12(isDark)
		} else {
			contentView.backgroundColor = .clear
		}
	}

	private func startObservingProgress(for item: OCItem) {
		let localID = item.localID as OCLocalID?
		if observedLocalID == localID {
			return
		}

		stopObservingProgress()
		observedLocalID = localID

		if let localID {
			progressObserver = NotificationCenter.default.addObserver(
				forName: .OCCoreItemChangedProgress,
				object: localID,
				queue: .main
			) { [weak self] _ in
				self?.refreshAccessoryState()
			}
		}

		if let activityUpdateNotificationName = clientContext?.core?.activityManager.activityUpdateNotificationName {
			activityObserver = NotificationCenter.default.addObserver(
				forName: activityUpdateNotificationName,
				object: nil,
				queue: .main
			) { [weak self] notification in
				self?.handleActivityUpdate(notification)
			}
		}
	}

	private func stopObservingProgress() {
		if let progressObserver {
			NotificationCenter.default.removeObserver(progressObserver)
			self.progressObserver = nil
		}
		observedLocalID = nil
		if let activityObserver {
			NotificationCenter.default.removeObserver(activityObserver)
			self.activityObserver = nil
		}
	}

	private func handleActivityUpdate(_ notification: Notification) {
		guard let item = configuredItem,
		      let updates = notification.userInfo?[OCActivityManagerNotificationUserInfoUpdatesKey] as? [[String: Any]] else {
			return
		}

		for update in updates {
			guard let activity = update[OCActivityManagerUpdateActivityKey] as? OCSyncRecordActivity,
			      activity.type == .download || activity.type == .upload,
			      let name = item.name, activity.localizedDescription.contains(name) else {
				continue
			}
			refreshAccessoryState()
			return
		}
	}

	private func refreshAccessoryState() {
		// OCCore posts OCCoreItemChangedProgress from its background queue. Mutating
		// Auto Layout off the main thread crashes NSISEngine. Hop asynchronously so
		// this cannot re-enter configure/layoutIfNeeded on the current run loop turn.
		OnMainThread { [weak self] in
			guard let self, let item = self.configuredItem else { return }
			self.updateDetailSegmentsIfNeeded(for: item, core: self.clientContext?.core)
			self.updateAccessoryAndProgress(
				for: item,
				layout: self.currentLayout,
				showsSelection: self.showsSelection,
				isSelected: self.selectionIndicator.isSelected,
				forceLayout: false
			)
			self.updateAccessibility(layout: self.currentLayout, showsListDetail: self.currentLayout == .list)
		}
	}

	private func updateDetailSegmentsIfNeeded(for item: OCItem, core: OCCore?) {
		let segmentsKey = "\(item.fileListStatusKey(core: core))|\(item.sizeLocalized)|\(item.lastModifiedLocalized)"
		guard configuredSegmentsKey != segmentsKey else { return }
		configuredSegmentsKey = segmentsKey
		detailSegmentView.items = item.fileListDetailSegments(core: core)
	}

	private func updateAccessoryAndProgress(for item: OCItem, layout: Layout, showsSelection: Bool, isSelected: Bool, forceLayout: Bool) {
		let transferProgress = item.fileListTransferProgress(for: clientContext)
		let canShowMore = layout == .list
			&& transferProgress == nil
			&& clientContext?.moreItemHandler != nil
			&& clientContext?.hasPermission(for: .moreOptions) != false
		let showsProgress = !showsSelection && transferProgress != nil && layout == .list
		let showsAccessory = canShowMore || showsProgress
		let needsLayout = currentLayout != layout
			|| self.showsSelection != showsSelection
			|| moreButton.isHidden == canShowMore
			|| progressView.isHidden == showsProgress

		self.showsSelection = showsSelection
		self.showsMoreButton = canShowMore

		selectionIndicator.isHidden = !showsSelection
		selectionIndicator.layout = layout
		selectionIndicator.isSelected = isSelected

		moreButton.isHidden = !canShowMore
		progressView.isHidden = !showsProgress
		progressView.progress = showsProgress ? transferProgress : nil
		if showsProgress {
			contentView.bringSubviewToFront(progressView)
		}
		if canShowMore {
			contentView.bringSubviewToFront(moreButton)
		}
		if showsSelection {
			contentView.bringSubviewToFront(selectionIndicator)
		}

		if forceLayout || needsLayout {
			applyLayout(layout, showsSelection: showsSelection, showsAccessory: showsAccessory)
		}

		updateSelectionAppearance(isSelected: isSelected)
	}

	private func updateAccessibility(layout: Layout, showsListDetail: Bool) {
		let statusAccessibility = detailSegmentView.items.compactMap(\.accessibilityLabel).joined(separator: ", ")
		accessibilityLabel = layout == .gridNoDetail
			? titleLabel.text
			: [titleLabel.text, showsListDetail ? statusAccessibility : (detailLabel.isHidden ? nil : detailLabel.text)]
				.compactMap { $0 }
				.filter { !$0.isEmpty }
				.joined(separator: ", ")
	}

	private func cancelIconRequest(core: OCCore?) {
		// Clear the property before stop() so a synchronous changeHandler cannot
		// read iconRequest while it is being mutated (Swift exclusivity crash).
		let previousRequest = iconRequest
		iconRequest = nil
		if let previousRequest {
			core?.vault.resourceManager?.stop(previousRequest)
		}
	}

	private func loadIcon(for item: OCItem, core: OCCore?, layout: Layout, reloadPlaceholder: Bool) {
		if reloadPlaceholder {
			cancelIconRequest(core: core)
			iconImageView.image = item.fileListIconImage(fitIn: iconSize(for: layout))
		}

		let iconSize = iconSize(for: layout)
		guard item.type == .file, item.thumbnailAvailability != .none, iconRequest == nil else {
			return
		}

		guard let resourceManager = core?.vault.resourceManager else {
			return
		}

		let request = OCResourceRequestItemThumbnail.request(
			for: item,
			maximumSize: iconSize,
			scale: UIScreen.main.scale,
			waitForConnectivity: true,
			changeHandler: { [weak self] request, _, _, _, newResource in
				guard let self else { return }
				// Compare by identifier to avoid exclusive-access clash on iconRequest === request.
				guard self.iconRequest?.identifier == request.identifier,
				      let resource = newResource as? OCResourceImage,
				      resource.quality == .normal,
				      let ocImage = resource.image else { return }

				let requestID = request.identifier
				_ = ocImage.request(for: iconSize, scale: UIScreen.main.scale) { _, _, _, image in
					OnMainThread {
						guard self.iconRequest?.identifier == requestID, let image else { return }
						self.iconImageView.image = image
					}
				}
			}
		)
		iconRequest = request
		resourceManager.start(request)
	}

	private func applyLayout(_ layout: Layout, showsSelection: Bool, showsAccessory: Bool) {
		currentLayout = layout
		NSLayoutConstraint.deactivate(layoutConstraints)
		layoutConstraints.removeAll()

		let horizontalMargin: CGFloat = 16
		let spacing: CGFloat = 12
		let selectionSize = Self.selectionIndicatorSize

		let trailingContentAnchor: NSLayoutXAxisAnchor
		let trailingContentConstant: CGFloat
		if showsAccessory, layout == .list {
			trailingContentAnchor = moreButton.isHidden ? progressView.leadingAnchor : moreButton.leadingAnchor
			trailingContentConstant = -spacing
		} else {
			trailingContentAnchor = contentView.trailingAnchor
			trailingContentConstant = -horizontalMargin
		}

		switch layout {
			case .list:
				titleLabel.isHidden = false
				titleLabel.numberOfLines = 1
				titleLabel.textAlignment = .left
				titleLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
				detailLabel.isHidden = true
				detailSegmentView.isHidden = false

				let iconLeadingAnchor: NSLayoutXAxisAnchor
				let iconLeadingConstant: CGFloat
				if showsSelection {
					iconLeadingAnchor = selectionIndicator.trailingAnchor
					iconLeadingConstant = spacing
				} else {
					iconLeadingAnchor = contentView.leadingAnchor
					iconLeadingConstant = horizontalMargin
				}

				layoutConstraints = [
					iconImageView.leadingAnchor.constraint(equalTo: iconLeadingAnchor, constant: iconLeadingConstant),
					iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
					iconImageView.widthAnchor.constraint(equalToConstant: Self.listIconSize),
					iconImageView.heightAnchor.constraint(equalToConstant: Self.listIconSize),

					titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: spacing),
					titleLabel.trailingAnchor.constraint(equalTo: trailingContentAnchor, constant: trailingContentConstant),
					titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

					detailSegmentView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
					detailSegmentView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
					detailSegmentView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
					detailSegmentView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
					detailSegmentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 16)
				]

			case .grid, .gridLowDetail, .gridNoDetail:
				let showsTitle = layout != .gridNoDetail
				let showsDetail = layout == .grid
				let textAreaHeight = FileListLayoutMetrics.gridTextAreaHeight(for: layout)

				titleLabel.isHidden = !showsTitle
				detailLabel.isHidden = !showsDetail
				detailSegmentView.isHidden = true

				if showsTitle {
					titleLabel.numberOfLines = 2
					titleLabel.textAlignment = .center
					titleLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize * 0.8)
				}

				if showsDetail {
					detailLabel.textAlignment = .center
				}

				layoutConstraints = [
					iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: FileListLayoutMetrics.gridIconHorizontalInset),
					iconImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -FileListLayoutMetrics.gridIconHorizontalInset),
					iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: FileListLayoutMetrics.gridIconTopInset),
					iconImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -textAreaHeight)
				]

				if layout != .gridNoDetail {
					layoutConstraints.append(
						iconImageView.heightAnchor.constraint(equalTo: iconImageView.widthAnchor, multiplier: FileListLayoutMetrics.gridIconAspect)
					)
				}

				if showsTitle {
					layoutConstraints.append(contentsOf: [
						titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: FileListLayoutMetrics.gridIconHorizontalInset),
						titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -FileListLayoutMetrics.gridIconHorizontalInset),
						titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: FileListLayoutMetrics.gridTitleSpacing),
						titleLabel.heightAnchor.constraint(lessThanOrEqualToConstant: FileListLayoutMetrics.gridTitleMaxHeight)
					])

					if showsDetail {
						layoutConstraints.append(contentsOf: [
							detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
							detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
							detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: FileListLayoutMetrics.gridDetailSpacing),
							detailLabel.heightAnchor.constraint(lessThanOrEqualToConstant: FileListLayoutMetrics.gridDetailHeight),
							detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -FileListLayoutMetrics.gridBottomInset)
						])
					} else {
						layoutConstraints.append(
							titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -FileListLayoutMetrics.gridBottomInset)
						)
					}
				}
		}

		if showsSelection {
			layoutConstraints.append(contentsOf: [
				selectionIndicator.widthAnchor.constraint(equalToConstant: selectionSize),
				selectionIndicator.heightAnchor.constraint(equalToConstant: selectionSize)
			])

			if layout == .list {
				layoutConstraints.append(contentsOf: [
					selectionIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalMargin),
					selectionIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
				])
			} else {
				layoutConstraints.append(contentsOf: [
					selectionIndicator.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
					selectionIndicator.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor)
				])
			}
		}

		if showsAccessory, layout == .list {
			layoutConstraints.append(contentsOf: [
				moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalMargin),
				moreButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
				progressView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
				progressView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
				progressView.widthAnchor.constraint(equalToConstant: 40),
				progressView.heightAnchor.constraint(equalToConstant: 40)
			])
		}

		NSLayoutConstraint.activate(layoutConstraints)
	}

	override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
		let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
		if currentLayout == .list {
			attributes.size.height = FileListLayoutMetrics.listItemHeight
		}
		return attributes
	}
}

private extension OCItem {
	func fileListIconImage(fitIn size: CGSize) -> UIImage? {
		if let image = icon(fitInSize: size) {
			return image
		}
		let fallbackIconName = type == .collection ? "folder" : "file"
		return Theme.shared.image(for: fallbackIconName, size: size)
	}

	var fileListDetailText: String {
		if type == .collection {
			return lastModifiedLocalizedCompact
		}
		return "\(sizeLocalized) · \(lastModifiedLocalizedCompact)"
	}

	func fileListStatusKey(core: OCCore?) -> String {
		let (icon, alpha, _) = cloudStatus(in: core)
		let coverage = core?.availableOfflinePolicyCoverage(of: self) ?? .none
		return "\(cloudStatus.rawValue)|\(coverage.rawValue)|\(icon != nil)|\(alpha)|\(isSharedWithUser)|\(sharedByUserOrGroup)|\(sharedByPublicLink)|\(state.rawValue)"
	}

	func fileListDetailSegments(core: OCCore?) -> [SegmentViewItem] {
		var detailItems: [SegmentViewItem] = []

		let (cloudStatusIcon, cloudStatusIconAlpha, accessibilityLabel) = cloudStatus(in: core)
		if let cloudStatusIcon {
			let segmentItem = SegmentViewItem(
				with: cloudStatusIcon.scaledImageFitting(in: CGSize(width: 32, height: 16)),
				style: .plain,
				lines: [.singleLine],
				accessibilityLabel: accessibilityLabel
			)
			segmentItem.insets = .zero
			segmentItem.alpha = cloudStatusIconAlpha
			detailItems.append(segmentItem)
		}

		if isSharedWithUser || sharedByUserOrGroup {
			let segmentItem = SegmentViewItem(
				with: OCItem.groupIcon?.scaledImageFitting(in: CGSize(width: 32, height: 16)),
				style: .plain,
				lines: [.singleLine],
				accessibilityLabel: OCLocalizedString("Shared", nil)
			)
			segmentItem.insets = .zero
			detailItems.append(segmentItem)
		}

		if sharedByPublicLink {
			let segmentItem = SegmentViewItem(
				with: OCItem.linkIcon?.scaledImageFitting(in: CGSize(width: 32, height: 16)),
				style: .plain,
				lines: [.singleLine],
				accessibilityLabel: OCLocalizedString("Shared by link", nil)
			)
			segmentItem.insets = .zero
			detailItems.append(segmentItem)
		}

		var detailString = sizeLocalized
		if location?.type == .drive, let core {
			detailString = driveQuotaLocalized(core: core)
		}
		if size < 0 {
			detailString = OCLocalizedString("Pending", nil)
		}
		if state == .serverSideProcessing {
			detailString = OCLocalizedString("Processing on server", nil)
		}

		detailString += " - " + lastModifiedLocalized

		let detailSegment = SegmentViewItem(
			with: nil,
			title: detailString,
			style: .plain,
			titleTextStyle: .footnote,
			lines: [.singleLine],
			accessibilityLabel: detailString
		)
		detailSegment.insets = .zero
		detailItems.append(detailSegment)

		return detailItems
	}

	func fileListTransferProgress(for context: ClientContext?) -> Progress? {
		let hasMessage = context?.inlineMessageCenter?.hasInlineMessage(for: self) ?? false
		if hasMessage {
			return nil
		}

		let hasSyncTransfer = syncActivity.rawValue & (OCItemSyncActivity.downloading.rawValue | OCItemSyncActivity.uploading.rawValue) != 0

		// Only cells whose item is actually transferring should show a ring.
		guard hasSyncTransfer else {
			return nil
		}

		guard let core = context?.core, let localID = self.localID else {
			return Progress(totalUnitCount: size > 0 ? Int64(size) : 1)
		}

		// Prefer progress registered for this item's localID.
		if let registeredProgresses = core.progressForItem(withLocalID: localID, matching: .none) {
			if let determinateProgress = registeredProgresses.first(where: { $0.totalUnitCount > 0 && !$0.isFinished && !$0.isCancelled }) {
				return determinateProgress
			}
			if let anyProgress = registeredProgresses.first(where: { !$0.isFinished && !$0.isCancelled }) {
				return anyProgress
			}
		}

		if let pipelineProgress = core.connection.liveDownloadTransferProgress(forItemLocalID: localID) as Progress?,
		   !pipelineProgress.isFinished,
		   !pipelineProgress.isCancelled {
			return pipelineProgress
		}

		// Activity manager match is name-based and ambiguous; only use it for this item
		// when the description clearly refers to this item's name.
		if let itemName = name, !itemName.isEmpty,
		   let activityProgress = fileListMatchingTransferActivityProgress(in: core, requiringNameMatch: true),
		   !(activityProgress.isFinished || activityProgress.isCancelled) {
			return activityProgress
		}

		// Placeholder ring while syncActivity says transfer is active but progress has not connected yet.
		return Progress(totalUnitCount: size > 0 ? Int64(size) : 1)
	}

	func fileListMatchingTransferActivityProgress(in core: OCCore, requiringNameMatch: Bool) -> Progress? {
		let activities = core.activityManager.activities
		let transferActivities = activities.compactMap { $0 as? OCSyncRecordActivity }.filter { $0.type == .upload || $0.type == .download }
		guard let itemName = name, !itemName.isEmpty else {
			return nil
		}

		let matchedActivity = transferActivities.first { $0.localizedDescription.contains(itemName) }
		if requiringNameMatch {
			return matchedActivity?.progress
		}

		if transferActivities.count == 1 {
			return transferActivities.first?.progress
		}
		return matchedActivity?.progress
	}
}

private enum FileListSelectionCheckbox {
	enum Style {
		case list
		case grid
	}

	static func image(isSelected: Bool, isDark: Bool, style: Style = .list) -> UIImage? {
		let checkboxImage: UIImage?
		switch style {
			case .list:
				if isSelected {
					checkboxImage = isDark ? HCIcon.checkboxFilledDark : HCIcon.checkboxFilledLight
				} else {
					checkboxImage = HCIcon.checkboxEmpty
				}
			case .grid:
				if isSelected {
					checkboxImage = isDark ? HCIcon.checkboxShadowFilledDark : HCIcon.checkboxShadowFilledLight
				} else {
					checkboxImage = isDark ? HCIcon.checkboxShadowEmptyDark : HCIcon.checkboxShadowEmptyLight
				}
		}
		return checkboxImage?.withRenderingMode(.alwaysOriginal)
	}
}

private final class FileListSelectionIndicator: UIImageView, Themeable {
	private var themeRegistered = false

	convenience init() {
		self.init(frame: .zero)
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	var isSelected = false {
		didSet { updateImage() }
	}

	var layout: FileListItemCell.Layout = .list {
		didSet {
			if layout != oldValue {
				updateImage()
			}
		}
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil, !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		updateImage()
	}

	private func updateImage() {
		let isDark = Theme.shared.activeCollection.isDark
		let style: FileListSelectionCheckbox.Style = layout.isGrid ? .grid : .list
		image = FileListSelectionCheckbox.image(isSelected: isSelected, isDark: isDark, style: style)
	}
}
