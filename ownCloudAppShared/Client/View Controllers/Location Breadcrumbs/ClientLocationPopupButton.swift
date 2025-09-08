//
//  ClientLocationPopupButton.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 23.10.23.
//  Copyright © 2023 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2023, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import ownCloudSDK
import Combine

open class ClientLocationPopupButton: ThemeCSSButton, UIPopoverPresentationControllerDelegate {
	weak var clientContext: ClientContext?
	open var location: OCLocation? {
		didSet {
			updateButton()
		}
	}

	public init(clientContext: ClientContext? = nil, location: OCLocation? = nil, excludeLastPathComponent: Bool = true) {
		super.init(frame: .zero)
		cssSelectors = [.title]

		self.clientContext = clientContext
		self.location = location

		titleLabel?.adjustsFontForContentSizeCategory = true
		semanticContentAttribute = .forceLeftToRight
		setContentHuggingPriority(.defaultHigh, for: .horizontal)
		setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
		showsMenuAsPrimaryAction = false
		translatesAutoresizingMaskIntoConstraints = false

		addAction(UIAction(handler: { [weak self] _ in
			self?.openLocationBrowser()
		}), for: .primaryActionTriggered)

		updateButton()
	}

	@objc private func openLocationBrowser() {
		guard
			let clientContext,
			let core = clientContext.core
		else { return }

		let repo = OCLocationTreeRepository(core: core)
		let dropdownVM = LocationTreeViewModel(repository: repo, anchorID: (location?.path ?? "") as OCPath)
		let dropdown = LocationTreeViewController(viewModel: dropdownVM, clientContext: clientContext)
		dropdown.modalPresentationStyle = UIModalPresentationStyle.popover
		dropdown.preferredContentSize = CGSize(width: 360, height: 44)
		if let pop = dropdown.popoverPresentationController {
			if let rootView = clientContext.rootViewController?.view {
				// Anchor horizontally centered in the root view, vertically aligned with the button
				let selfRectInRoot = self.convert(self.bounds, to: rootView)
				let anchorRect = centeredAnchorRect(in: rootView, y: selfRectInRoot.midY)
				pop.sourceView = rootView
				pop.sourceRect = anchorRect
			} else {
				pop.sourceView = self
				pop.sourceRect = self.bounds
			}
			pop.backgroundColor = Theme.shared.activeCollection.css.getColor(.fill, selectors: [.locationDropDown], for: nil)
			pop.permittedArrowDirections = UIPopoverArrowDirection([.up, .down])
			pop.delegate = self
		}

		clientContext.rootViewController?.present(dropdown, animated: true)
	}

	private func centeredAnchorRect(in rootView: UIView, y: CGFloat) -> CGRect {
		let centerX = rootView.bounds.midX
		return CGRect(x: centerX - 1, y: y, width: 2, height: 2)
	}

	open override func didMoveToWindow() {
		super.didMoveToWindow()

		self.updateButton()
	}

	func updateButton() {
		let title = location?.displayName(in: clientContext).redacted() ?? "-"
		let attributedTitle = AttributedString(NSAttributedString(string: title, attributes: [
			.font : UIFont.systemFont(ofSize: UIFont.buttonFontSize, weight: .semibold),
			.foregroundColor: Theme.shared.activeCollection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		]))
		let chevronImage = UIImage(named: "chevron-down", in: Bundle.sharedAppBundle, with: nil)

		var buttonConfig = configuration ?? .plain()
		buttonConfig.imagePadding = 5
		buttonConfig.imagePlacement = .trailing
		buttonConfig.attributedTitle = attributedTitle
		#if swift(>=5.9) // workaround build issue on Xcode 14.2 (GitHub actions)
		buttonConfig.titleLineBreakMode = .byTruncatingTail
		#endif
		buttonConfig.image = chevronImage
		buttonConfig.imageColorTransformer = UIConfigurationColorTransformer { _ in
			return Theme.shared.activeThemeCSS.getColor(.fill, selectors: [.text], for: nil) ?? .black
		}
		configuration = buttonConfig
	}

	// MARK: - UIPopoverPresentationControllerDelegate
	public func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		return .none
	}

	public func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
		return .none
	}

	public func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController) {
		if let rootView = clientContext?.rootViewController?.view {
			let selfRectInRoot = self.convert(self.bounds, to: rootView)
			popoverPresentationController.sourceRect = centeredAnchorRect(in: rootView, y: selfRectInRoot.midY)
		}
	}

	public func popoverPresentationController(_ popoverPresentationController: UIPopoverPresentationController, willRepositionPopoverTo rect: UnsafeMutablePointer<CGRect>, in view: UnsafeMutablePointer<UIView>) {
		if let rootView = clientContext?.rootViewController?.view {
			let selfRectInRoot = self.convert(self.bounds, to: rootView)
			rect.pointee = centeredAnchorRect(in: rootView, y: selfRectInRoot.midY)
			view.pointee = rootView
		}
	}

	required public init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		updateButton()
	}
}
