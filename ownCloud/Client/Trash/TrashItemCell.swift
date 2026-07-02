//
//  TrashItemCell.swift
//  ownCloud
//
//  Copyright © 2025 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2025, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import ownCloudSDK
import ownCloudAppShared
import UniformTypeIdentifiers

final class TrashItemCell: UICollectionViewCell, Themeable {

	enum Layout {
		case list
		case grid
	}

	private static let listIconSize: CGFloat = 40
	private static let selectionIndicatorSize: CGFloat = 24

	private let iconImageView = UIImageView()
	private let titleLabel = UILabel()
	private let detailLabel = UILabel()
	private let selectionIndicator = TrashSelectionIndicator()

	private var layoutConstraints: [NSLayoutConstraint] = []
	private var currentLayout: Layout = .list
	private var showsSelection = false
	private var themeRegistered = false
	private var isDark = false
	private var iconRequest: OCResourceRequest?
	private var configuredItemKey: String?

	override init(frame: CGRect) {
		super.init(frame: frame)

		iconImageView.translatesAutoresizingMaskIntoConstraints = false
		iconImageView.contentMode = .scaleAspectFit
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		detailLabel.translatesAutoresizingMaskIntoConstraints = false
		selectionIndicator.translatesAutoresizingMaskIntoConstraints = false

		titleLabel.numberOfLines = 1
		titleLabel.lineBreakMode = .byTruncatingMiddle
		titleLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)

		detailLabel.numberOfLines = 1
		detailLabel.lineBreakMode = .byTruncatingTail
		detailLabel.font = UIFont.preferredFont(forTextStyle: .footnote)

		contentView.addSubview(iconImageView)
		contentView.addSubview(titleLabel)
		contentView.addSubview(detailLabel)
		contentView.addSubview(selectionIndicator)

		applyLayout(.list, showsSelection: false)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		if themeRegistered {
			Theme.shared.unregister(client: self)
		}
	}

	override func prepareForReuse() {
		super.prepareForReuse()
		iconRequest = nil
		configuredItem = nil
		configuredItemKey = nil
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
		layout: Layout,
		showsSelection: Bool,
		isSelected: Bool
	) {
		TrashDebugLogging.log(item: item, context: "TrashItemCell.configure")
		TrashDebugLogging.log("TrashItemCell.configure core=\(core != nil ? "present" : "nil") resourceManager=\(core?.vault.resourceManager != nil ? "present" : "nil") layout=\(layout)")

		let itemKey = item.path ?? item.fileID ?? item.eTag ?? item.name ?? ""
		let itemConfigurationKey = "\(itemKey)|\(layout)|\(showsSelection)|\(isSelected)"
		let shouldReloadIcon = itemConfigurationKey != configuredItemKey
		configuredItemKey = itemConfigurationKey

		let needsLayoutUpdate = layout != currentLayout || showsSelection != self.showsSelection
		self.showsSelection = showsSelection
		selectionIndicator.isHidden = !showsSelection
		selectionIndicator.layout = layout
		selectionIndicator.isSelected = isSelected

		if needsLayoutUpdate {
			applyLayout(layout, showsSelection: showsSelection)
		}

		configuredItem = item
		titleLabel.text = item.trashDisplayName
		detailLabel.text = item.trashDetailText
		detailLabel.isHidden = false

		loadIcon(for: item, core: core, layout: layout, reloadPlaceholder: shouldReloadIcon)
		updateSelectionAppearance(isSelected: isSelected)
		accessibilityLabel = [titleLabel.text, detailLabel.text].compactMap { $0 }.joined(separator: ", ")
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		isDark = collection.isDark
		titleLabel.textColor = HCColor.Content.textPrimary(collection.isDark)
		detailLabel.textColor = HCColor.Content.textSecondary(collection.isDark)
		contentView.backgroundColor = .clear
		backgroundColor = .clear
		updateSelectionAppearance(isSelected: selectionIndicator.isSelected)
		if event != .initial, let item = configuredItem {
			iconImageView.image = item.trashIconImage(fitIn: iconSize(for: currentLayout))
		}
	}

	private var configuredItem: OCItem?

	private func iconSize(for layout: Layout) -> CGSize {
		layout == .list
			? CGSize(width: Self.listIconSize, height: Self.listIconSize)
			: CGSize(width: 120, height: 120)
	}

	private func updateSelectionAppearance(isSelected: Bool) {
		if showsSelection, isSelected {
			contentView.backgroundColor = HCColor.Interaction.secondaryTransparentPressed12(isDark)
		} else {
			contentView.backgroundColor = .clear
		}
	}

	private func loadIcon(for item: OCItem, core: OCCore?, layout: Layout, reloadPlaceholder: Bool) {
		if reloadPlaceholder {
			if let previousRequest = iconRequest {
				core?.vault.resourceManager?.stop(previousRequest)
			}
			iconRequest = nil

			let iconSize = iconSize(for: layout)
			item.trashApplyPresentationMimeType()
			iconImageView.image = item.trashIconImage(fitIn: iconSize)
		}

		let iconSize = iconSize(for: layout)

		TrashDebugLogging.log("""
		TrashItemCell.loadIcon: \
		iconSize=\(iconSize) \
		effectiveMime=\(item.trashEffectiveMimeType ?? "nil") \
		iconName=\(item.iconName ?? "nil") \
		iconImage=\(iconImageView.image != nil ? "present(\(iconImageView.image?.size ?? .zero))" : "nil") \
		supportsThumbnail=\(item.trashSupportsThumbnail) \
		thumbnailAvailability=\(item.thumbnailAvailability.rawValue) \
		reloadPlaceholder=\(reloadPlaceholder)
		""")

		guard item.trashSupportsThumbnail, iconRequest == nil else {
			if !item.trashSupportsThumbnail {
				TrashDebugLogging.log("TrashItemCell.loadIcon: skipping thumbnail request")
			}
			return
		}

		guard let resourceManager = core?.vault.resourceManager else {
			TrashDebugLogging.log("TrashItemCell.loadIcon: no resourceManager — thumbnail request not started")
			return
		}

		let request = OCResourceRequestItemThumbnail.request(
			for: item,
			maximumSize: iconSize,
			scale: UIScreen.main.scale,
			waitForConnectivity: true,
			changeHandler: { [weak self] request, error, isOngoing, _, newResource in
				let resource = newResource as? OCResourceImage
				TrashDebugLogging.log("""
				TrashItemCell.thumbnailChange: \
				ongoing=\(isOngoing) \
				error=\(error?.localizedDescription ?? "nil") \
				quality=\(resource?.quality.rawValue ?? -1) \
				hasOCImage=\(resource?.image != nil) \
				requestEnded=\(request.ended)
				""")

				guard let self,
				      self.iconRequest === request,
				      let resource,
				      resource.quality == .normal,
				      let ocImage = resource.image else { return }

				_ = ocImage.request(for: iconSize, scale: UIScreen.main.scale) { _, imageError, _, image in
					TrashDebugLogging.log("""
					TrashItemCell.thumbnailDecode: \
					error=\(imageError?.localizedDescription ?? "nil") \
					uiImage=\(image != nil ? "present(\(image?.size ?? .zero))" : "nil")
					""")

					OnMainThread {
						guard self.iconRequest === request, let image else { return }
						self.iconImageView.image = image
						TrashDebugLogging.log("TrashItemCell.thumbnailDecode: applied UIImage to iconImageView")
					}
				}
			}
		)
		iconRequest = request
		TrashDebugLogging.log("TrashItemCell.loadIcon: starting thumbnail request id=\(request.identifier ?? "nil")")
		resourceManager.start(request)
	}

	private func applyLayout(_ layout: Layout, showsSelection: Bool) {
		currentLayout = layout
		NSLayoutConstraint.deactivate(layoutConstraints)
		layoutConstraints.removeAll()

		let horizontalMargin: CGFloat = 16
		let spacing: CGFloat = 12
		let selectionSize = Self.selectionIndicatorSize
		let trailingAnchor = showsSelection
			? selectionIndicator.leadingAnchor
			: contentView.trailingAnchor
		let trailingConstant: CGFloat = showsSelection ? -spacing : -horizontalMargin

		switch layout {
			case .list:
				titleLabel.numberOfLines = 1
				titleLabel.textAlignment = .left
				titleLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
				detailLabel.textAlignment = .left
				detailLabel.isHidden = false

				layoutConstraints = [
					iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalMargin),
					iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
					iconImageView.widthAnchor.constraint(equalToConstant: Self.listIconSize),
					iconImageView.heightAnchor.constraint(equalToConstant: Self.listIconSize),

					titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: spacing),
					titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: trailingConstant),
					titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

					detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
					detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
					detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
					detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10)
				]

			case .grid:
				titleLabel.numberOfLines = 2
				titleLabel.textAlignment = .center
				titleLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize * 0.8)
				detailLabel.textAlignment = .center
				detailLabel.isHidden = false

				layoutConstraints = [
					iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: TrashLayoutMetrics.gridIconHorizontalInset),
					iconImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -TrashLayoutMetrics.gridIconHorizontalInset),
					iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: TrashLayoutMetrics.gridIconTopInset),
					iconImageView.heightAnchor.constraint(equalTo: iconImageView.widthAnchor, multiplier: TrashLayoutMetrics.gridIconAspect),

					titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: TrashLayoutMetrics.gridIconHorizontalInset),
					titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -TrashLayoutMetrics.gridIconHorizontalInset),
					titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: TrashLayoutMetrics.gridTitleSpacing),
					titleLabel.heightAnchor.constraint(lessThanOrEqualToConstant: TrashLayoutMetrics.gridTitleMaxHeight),

					detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
					detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
					detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: TrashLayoutMetrics.gridDetailSpacing),
					detailLabel.heightAnchor.constraint(lessThanOrEqualToConstant: TrashLayoutMetrics.gridDetailHeight),
					detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -TrashLayoutMetrics.gridBottomInset)
				]
		}

		if showsSelection {
			layoutConstraints.append(contentsOf: [
				selectionIndicator.widthAnchor.constraint(equalToConstant: selectionSize),
				selectionIndicator.heightAnchor.constraint(equalToConstant: selectionSize)
			])

			if layout == .list {
				layoutConstraints.append(contentsOf: [
					selectionIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalMargin),
					selectionIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
				])
			} else {
				layoutConstraints.append(contentsOf: [
					selectionIndicator.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
					selectionIndicator.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor)
				])
			}
		}

		NSLayoutConstraint.activate(layoutConstraints)
	}

	override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
		let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
		if currentLayout == .list {
			attributes.size.height = TrashLayoutMetrics.listItemHeight
		}
		return attributes
	}
}

private extension OCItem {
	func trashIconImage(fitIn size: CGSize) -> UIImage? {
		trashApplyPresentationMimeType()

		if let image = icon(fitInSize: size) {
			TrashDebugLogging.log("trashIconImage: using OCItem.icon iconName=\(iconName ?? "nil") size=\(size)")
			return image
		}

		let fallbackIconName = type == .collection ? "folder" : "file"
		let fallbackImage = Theme.shared.image(for: fallbackIconName, size: size)
		TrashDebugLogging.log("trashIconImage: fallback iconName=\(fallbackIconName) image=\(fallbackImage != nil ? "present" : "nil")")
		return fallbackImage
	}

	var trashSupportsThumbnail: Bool {
		type == .file && thumbnailAvailability != .none
	}

	var trashDisplayName: String {
		if let trashName = value(forLocalAttribute: OCLocalAttribute.trashOriginalFilename) as? String, !trashName.isEmpty {
			return trashName
		}
		return name ?? ""
	}

	var trashDetailText: String {
		if isPendingTrashItem {
			return HCL10n.Trash.pendingSync
		}
		guard let daysLeft = trashDaysUntilPermanentDeletion else {
			return HCL10n.Trash.daysLeftUnknown
		}
		return HCL10n.Trash.daysUntilDeletion(daysLeft)
	}

	var trashDaysUntilPermanentDeletion: Int? {
		guard let trashedDate = trashDeletionDate else { return nil }

		let calendar = Calendar.current
		let startOfToday = calendar.startOfDay(for: Date())
		guard let purgeDate = calendar.date(
			byAdding: .day,
			value: TrashLayoutMetrics.retentionPeriodDays,
			to: calendar.startOfDay(for: trashedDate)
		) else {
			return nil
		}

		let days = calendar.dateComponents([.day], from: startOfToday, to: purgeDate).day ?? 0
		return max(0, days)
	}

	var trashDeletionDate: Date? {
		if let value = value(forLocalAttribute: OCLocalAttribute.trashDeletionTimestamp) {
			if let date = value as? Date {
				return date
			}
			if let timestamp = value as? NSNumber {
				return Date(timeIntervalSince1970: timestamp.doubleValue)
			}
			if let string = value as? String, !string.isEmpty {
				return TrashItemDateParser.parse(string)
			}
		}
		return trashDeletionDateFromFilename
	}

	private var trashDeletionDateFromFilename: Date? {
		guard let name else { return nil }
		guard let dotDRange = name.range(of: ".d", options: .backwards) else { return nil }
		let suffix = String(name[dotDRange.upperBound...])
		guard let timestamp = TimeInterval(suffix), timestamp > 0 else { return nil }
		return Date(timeIntervalSince1970: timestamp)
	}
}

private enum TrashItemDateParser {
	private static let httpDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
		return formatter
	}()

	private static let iso8601Formatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	static func parse(_ value: String) -> Date? {
		if let date = httpDateFormatter.date(from: value) {
			return date
		}
		if let date = iso8601Formatter.date(from: value) {
			return date
		}
		let fallbackISO8601 = ISO8601DateFormatter()
		return fallbackISO8601.date(from: value)
	}
}

enum TrashSelectionCheckbox {
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

private final class TrashSelectionIndicator: UIImageView, Themeable {
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

	var layout: TrashItemCell.Layout = .list {
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
		let style: TrashSelectionCheckbox.Style = layout == .grid ? .grid : .list
		image = TrashSelectionCheckbox.image(isSelected: isSelected, isDark: isDark, style: style)
		layer.shadowOpacity = 0
	}
}
