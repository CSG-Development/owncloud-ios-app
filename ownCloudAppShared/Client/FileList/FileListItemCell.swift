//
//  FileListItemCell.swift
//  ownCloudAppShared
//
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2026, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 */

import UIKit
import ownCloudSDK

final class FileListItemCell: UICollectionViewCell, Themeable {

	enum Layout {
		case list
		case grid
	}

	private static let listIconSize: CGFloat = 40
	private static let selectionIndicatorSize: CGFloat = 24

	private let iconImageView = UIImageView()
	private let titleLabel = UILabel()
	private let detailLabel = UILabel()
	private let selectionIndicator = FileListSelectionIndicator()

	private var layoutConstraints: [NSLayoutConstraint] = []
	private var currentLayout: Layout = .list
	private var showsSelection = false
	private var themeRegistered = false
	private var isDark = false
	private var iconRequest: OCResourceRequest?
	private var configuredItemKey: String?
	private var configuredItem: OCItem?

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
		let itemKey = item.localID ?? item.fileID ?? item.path ?? item.name ?? ""
		let itemConfigurationKey = "\(itemKey)|\(layout)|\(showsSelection)|\(isSelected)|\(item.sizeLocalized)|\(item.lastModifiedLocalizedCompact)"
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
		titleLabel.text = item.name ?? ""
		detailLabel.text = item.fileListDetailText
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
			iconImageView.image = item.fileListIconImage(fitIn: iconSize(for: currentLayout))
		}
	}

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
				guard let self,
				      self.iconRequest === request,
				      let resource = newResource as? OCResourceImage,
				      resource.quality == .normal,
				      let ocImage = resource.image else { return }

				_ = ocImage.request(for: iconSize, scale: UIScreen.main.scale) { _, _, _, image in
					OnMainThread {
						guard self.iconRequest === request, let image else { return }
						self.iconImageView.image = image
					}
				}
			}
		)
		iconRequest = request
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
					iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: FileListLayoutMetrics.gridIconHorizontalInset),
					iconImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -FileListLayoutMetrics.gridIconHorizontalInset),
					iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: FileListLayoutMetrics.gridIconTopInset),
					iconImageView.heightAnchor.constraint(equalTo: iconImageView.widthAnchor, multiplier: FileListLayoutMetrics.gridIconAspect),

					titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: FileListLayoutMetrics.gridIconHorizontalInset),
					titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -FileListLayoutMetrics.gridIconHorizontalInset),
					titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: FileListLayoutMetrics.gridTitleSpacing),
					titleLabel.heightAnchor.constraint(lessThanOrEqualToConstant: FileListLayoutMetrics.gridTitleMaxHeight),

					detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
					detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
					detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: FileListLayoutMetrics.gridDetailSpacing),
					detailLabel.heightAnchor.constraint(lessThanOrEqualToConstant: FileListLayoutMetrics.gridDetailHeight),
					detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -FileListLayoutMetrics.gridBottomInset)
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
		let style: FileListSelectionCheckbox.Style = layout == .grid ? .grid : .list
		image = FileListSelectionCheckbox.image(isSelected: isSelected, isDark: isDark, style: style)
	}
}
