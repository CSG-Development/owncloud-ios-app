//
//  MoreViewHeader.swift
//  ownCloud
//
//  Created by Pablo Carrascal on 17/08/2018.
//  Copyright © 2018 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2018, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import ownCloudSDK

open class MoreViewHeader: UIView {
	private lazy var iconView: ResourceViewHost = {
		let view = ResourceViewHost()
		view.contentMode = .scaleAspectFit
		view.setContentHuggingPriority(.required, for: .horizontal)
		view.setContentHuggingPriority(.required, for: .vertical)
		view.setContentCompressionResistancePriority(.required, for: .horizontal)
		view.setContentCompressionResistancePriority(.required, for: .vertical)
		return view
	}()

	private lazy var labelContainerView: UIView = {
		let view = UIView()
		view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		view.setContentCompressionResistancePriority(.required, for: .vertical)
		return view
	}()

	private lazy var contentContainerView: UIView = {
		let view = UIView()

		return view
	}()

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.font = UIFont.systemFont(ofSize: 17, weight: UIFont.Weight.semibold)
		label.lineBreakMode = .byWordWrapping
		label.numberOfLines = 0
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		label.setContentCompressionResistancePriority(.required, for: .vertical)
		label.setContentHuggingPriority(.defaultLow, for: .horizontal)
		label.setContentHuggingPriority(.defaultLow, for: .vertical)
		return label
	}()

	private lazy var detailLabel: UILabel = {
		let label = UILabel()
		label.font = UIFont.systemFont(ofSize: 14)
		label.lineBreakMode = .byTruncatingTail
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		label.setContentCompressionResistancePriority(.required, for: .vertical)
		label.setContentHuggingPriority(.defaultLow, for: .horizontal)
		label.setContentHuggingPriority(.defaultLow, for: .vertical)
		return label
	}()

	public lazy var rightContainer: UIStackView = {
		let stackView = UIStackView()
		stackView.translatesAutoresizingMaskIntoConstraints = false
		stackView.axis = .horizontal
		stackView.spacing = 8
		stackView.alignment = .center
		stackView.setContentCompressionResistancePriority(.required, for: .horizontal)
		stackView.setContentCompressionResistancePriority(.required, for: .vertical)
		return stackView
	}()

	private lazy var favoriteButton: UIButton = {
		let button = UIButton()
		button.addTarget(self, action: #selector(toogleFavoriteState), for: UIControl.Event.touchUpInside)
		button.isPointerInteractionEnabled = true
		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		button.setContentCompressionResistancePriority(.required, for: .vertical)
		button.snp.makeConstraints { $0.width.height.equalTo(24) }
		return button
	}()

	public lazy var activityIndicator: UIActivityIndicatorView = {
		let activityIndicator = UIActivityIndicatorView(style: .medium)
		activityIndicator.setContentCompressionResistancePriority(.required, for: .horizontal)
		activityIndicator.setContentCompressionResistancePriority(.required, for: .vertical)
		activityIndicator.snp.makeConstraints { $0.width.height.equalTo(24) }
		return activityIndicator
	}()

	public var thumbnailSize = CGSize(width: 60, height: 60)

	public var showFavoriteButton: Bool
	public var showActivityIndicator: Bool
	public var adaptBackgroundColor : Bool

	public var item: OCItem
	public weak var core: OCCore?
	public var url: URL?

	public init(for item: OCItem, with core: OCCore, favorite: Bool = true, adaptBackgroundColor: Bool = false, showActivityIndicator: Bool = false) {
		self.item = item
		self.core = core
		self.showFavoriteButton = favorite && core.bookmark.hasCapability(.favorites)
		self.showActivityIndicator = showActivityIndicator

		self.adaptBackgroundColor = adaptBackgroundColor

		super.init(frame: .zero)

		setupView()
	}

	public init(url: URL) {
		self.showFavoriteButton = false
		self.showActivityIndicator = false
		self.adaptBackgroundColor = false
		self.item = OCItem()
		self.url = url

		super.init(frame: .zero)

		setupView()
	}

	deinit {
		Theme.shared.unregister(client: self)
	}

	private func setupView() {
		cssSelectors = [.more, .header]

		contentContainerView.addSubview(iconView)
		iconView.snp.makeConstraints {
			$0.width.equalTo(thumbnailSize.width)
			$0.height.equalTo(thumbnailSize.height)
			$0.leading.equalToSuperview().offset(20)
			$0.top.equalToSuperview().offset(20)
			$0.bottom.lessThanOrEqualToSuperview().offset(-20)
		}

		contentContainerView.addSubview(rightContainer)
		rightContainer.snp.makeConstraints {
			$0.centerY.equalToSuperview()
			$0.trailing.equalToSuperview().offset(-20)
		}
		rightContainer.addArrangedSubview(favoriteButton)
		rightContainer.addArrangedSubview(activityIndicator)

		contentContainerView.addSubview(labelContainerView)
		labelContainerView.addSubview(titleLabel)
		labelContainerView.addSubview(detailLabel)

		titleLabel.snp.makeConstraints {
			$0.leading.trailing.top.equalToSuperview()
		}
		detailLabel.snp.makeConstraints {
			$0.top.equalTo(titleLabel.snp.bottom).offset(5)
			$0.leading.trailing.bottom.equalToSuperview()
		}

		labelContainerView.snp.makeConstraints {
			$0.top.equalToSuperview().offset(20)
			$0.bottom.equalToSuperview().offset(-20)
			$0.leading.equalTo(iconView.snp.trailing).offset(10)
			$0.trailing.equalTo(rightContainer.snp.leading).offset(-10)
		}

		let wrappedContentContainerView = contentContainerView.withScreenshotProtection
		self.addSubview(wrappedContentContainerView)
		wrappedContentContainerView.snp.makeConstraints { $0.edges.equalToSuperview() }

		favoriteButton.isHidden = !showFavoriteButton
		activityIndicator.isHidden = !showActivityIndicator
		updateFavoriteButtonImage()

		if let url = url {
			titleLabel.attributedText = NSAttributedString(string: url.lastPathComponent, attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17, weight: .semibold)])

			do {
				let attr = try FileManager.default.attributesOfItem(atPath: url.path)

				if let fileSize = attr[FileAttributeKey.size] as? UInt64 {
					let byteCountFormatter = ByteCountFormatter()
					byteCountFormatter.countStyle = .file
					let size = byteCountFormatter.string(fromByteCount: Int64(fileSize))

					detailLabel.attributedText =  NSAttributedString(string: size, attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 14, weight: .regular)])
				}
			} catch {
				print("Error: \(error)")
			}
		} else {
			var itemName = item.name

			if item.isRoot {
				if let core, core.useDrives, let driveID = item.driveID {
					if let drive = core.drive(withIdentifier: driveID, attachedOnly: false) {
						itemName = drive.name
					}
				} else {
					itemName = OCLocalizedString("Files", nil)
				}
			}

			titleLabel.attributedText = NSAttributedString(string: itemName?.redacted() ?? "", attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17, weight: .semibold)])

			let byteCountFormatter = ByteCountFormatter()
			byteCountFormatter.countStyle = .file
			var size = byteCountFormatter.string(fromByteCount: Int64(item.size))

			if item.size < 0 {
				size = OCLocalizedString("Pending", nil)
			}

			let dateString = item.lastModifiedLocalized

			let detail = size + " - " + dateString

			detailLabel.attributedText =  NSAttributedString(string: detail, attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 14, weight: .regular)])
		}

		let iconRequest = OCResourceRequestItemThumbnail.request(for: item, maximumSize: thumbnailSize, scale: 0, waitForConnectivity: true, changeHandler: nil)
		self.iconView.request = iconRequest
		core?.vault.resourceManager?.start(iconRequest)

		self.secureView(core: core)
	}

	open override func layoutSubviews() {
		super.layoutSubviews()

		// Update wrapping widths without triggering another layout pass
		let availableLabelWidth = labelContainerView.bounds.width
		if availableLabelWidth > 0 {
			if titleLabel.preferredMaxLayoutWidth != availableLabelWidth {
				titleLabel.preferredMaxLayoutWidth = availableLabelWidth
			}
			if detailLabel.preferredMaxLayoutWidth != availableLabelWidth {
				detailLabel.preferredMaxLayoutWidth = availableLabelWidth
			}
		}
	}

	open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)

		// Defer a light layout pass only to avoid nested layout/invalidation loops
		DispatchQueue.main.async { [weak self] in
			self?.setNeedsLayout()
		}
	}

	public func updateHeader(title: String, subtitle: String) {
		titleLabel.text = title.redacted()
		detailLabel.text = subtitle.redacted()
	}

	public required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc public func toogleFavoriteState() {
		if item.isFavorite == true {
			item.isFavorite = false
		} else {
			item.isFavorite = true
		}
		self.updateFavoriteButtonImage()
		core?.update(item, properties: [OCItemPropertyName.isFavorite], options: nil, resultHandler: { (error, _, _, _) in
			if error == nil {
				OnMainThread {
					self.updateFavoriteButtonImage()
				}
			}
		})
	}

	public func updateFavoriteButtonImage() {
		if item.isFavorite == true {
			favoriteButton.cssSelectors = [.favorite]
			favoriteButton.setImage(UIImage(named: "star"), for: .normal)
			favoriteButton.accessibilityLabel = OCLocalizedString("Unfavorite item", nil)
		} else {
			favoriteButton.cssSelectors = [.disabled, .favorite]
			favoriteButton.setImage(UIImage(named: "unstar"), for: .normal)
			favoriteButton.accessibilityLabel = OCLocalizedString("Favorite item", nil)
		}

		favoriteButton.tintColor = Theme.shared.activeCollection.css.getColor(.stroke, for: favoriteButton)
	}

	private var _hasRegistered = false
	open override func didMoveToWindow() {
		super.didMoveToWindow()

		if window != nil, !_hasRegistered {
			_hasRegistered = true
			Theme.shared.register(client: self)
		}
	}
}

extension MoreViewHeader: Themeable {
	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		titleLabel.applyThemeCollection(collection)
		detailLabel.applyThemeCollection(collection, itemStyle: .message)
		activityIndicator.style = collection.css.getActivityIndicatorStyle(for: activityIndicator) ?? .medium

		if adaptBackgroundColor {
			backgroundColor = collection.css.getColor(.fill, for: self)
		}

		updateFavoriteButtonImage()
	}
}
