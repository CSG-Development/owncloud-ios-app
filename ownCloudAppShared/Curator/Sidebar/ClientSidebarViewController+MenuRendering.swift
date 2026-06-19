import UIKit
import ownCloudSDK
import ownCloudApp

extension ClientSidebarViewController {

	// MARK: - Menu reload

	public func reloadMenu(animated: Bool) {
		rowViewsByItemRef.removeAll()
		rowContainersByItemRef.removeAll()
		contentStackView.arrangedSubviews.forEach {
			contentStackView.removeArrangedSubview($0)
			$0.removeFromSuperview()
		}

		for accountController in dataModel.accountControllers {
			let entries = SidebarMenuBuilder.entries(for: accountController, expandedFolderRefs: expandedFolderRefs)
			for entry in entries {
				contentStackView.addArrangedSubview(makeRowContainer(for: entry, accountController: accountController))
			}
		}

		if let sidebarLinks = Branding.shared.sidebarLinks, !sidebarLinks.isEmpty {
			contentStackView.addArrangedSubview(makeSeparator())
			if let title = Branding.shared.sidebarLinksTitle {
				contentStackView.addArrangedSubview(makeSectionTitle(title))
			}
			for link in sidebarLinks {
				let image: UIImage? = {
					if let symbol = link.symbol { return OCSymbol.icon(forSymbolName: symbol) }
					if let name = link.image { return UIImage(named: name)?.scaledImageFitting(in: CGSize(width: 30, height: 30)) }
					return nil
				}()
				let action = OCAction(title: link.title, icon: image, action: { [weak self] _, _, completion in
					self?.openURL(link.url)
					completion(nil)
				})
				action.automaticDeselection = true
				contentStackView.addArrangedSubview(makeRowContainer(for: SidebarMenuBuilder.entries(for: action), accountController: nil))
			}
		}

		contentStackView.addArrangedSubview(makeSeparator())

		let settingsAction = OCAction(
			title: OCLocalizedString("Settings", nil),
			icon: UIImage(named: "settings_thin", in: Bundle.sharedAppBundle, with: nil),
			action: { [weak self] _, _, completion in self?.onSettingsTap?(); completion(nil) }
		)
		settingsAction.automaticDeselection = true

		let signOutAction = OCAction(
			title: HCL10n.Sidebar.signOut,
			icon: UIImage(named: "sign_out", in: Bundle.sharedAppBundle, with: nil),
			action: { [weak self] _, _, completion in self?.onSignoutTap?(); completion(nil) }
		)
		signOutAction.automaticDeselection = true

		contentStackView.addArrangedSubview(makeRowContainer(for: SidebarMenuBuilder.entries(for: settingsAction), accountController: nil))
		contentStackView.addArrangedSubview(makeRowContainer(for: SidebarMenuBuilder.entries(for: signOutAction), accountController: nil))
		contentStackView.addArrangedSubview(makeFooterContainer(footerViewDouble))

		applyHighlightState()
		updateShouldShowDouble()
	}

	// MARK: - View factories

	/// Wraps a row view in a padded container and registers it by item reference.
	func makeRowContainer(for entry: SidebarMenuEntry, accountController: AccountController?) -> UIView {
		let row = makeRow(for: entry, accountController: accountController)
		let container = UIView()
		container.addSubview(row)
		row.snp.makeConstraints {
			$0.top.bottom.equalToSuperview()
			$0.leading.trailing.equalToSuperview().inset(MenuAnimation.horizontalInset)
		}
		rowContainersByItemRef[entry.itemReference] = container
		return container
	}

	private func makeRow(for entry: SidebarMenuEntry, accountController: AccountController?) -> HCSidebarMenuRowView {
		let row = HCSidebarMenuRowView(frame: .zero)
		row.title = entry.title
		row.icon = entry.icon
		row.indentLevel = entry.indentLevel
		row.isRowSelected = highlightedItemRefs.contains { $0.isEqual(entry.itemReference) }

		if entry.kind == .folder {
			row.setDisclosureExpanded(
				expandedFolderRefs.contains { $0.isEqual(entry.itemReference) },
				animated: false
			)
		}

		rowViewsByItemRef[entry.itemReference] = row
		row.onTap = { [weak self] in self?.handleRowTap(entry: entry, accountController: accountController) }
		return row
	}

	func makeFooterContainer(_ footer: UIView) -> UIView {
		let container = UIView()
		container.addSubview(footer)
		footer.snp.makeConstraints {
			$0.top.bottom.equalToSuperview()
			$0.leading.trailing.equalToSuperview().inset(MenuAnimation.horizontalInset)
		}
		return container
	}

	func makeSeparator() -> UIView {
		let container = UIView()
		let separator = HCSeparatorView(frame: .zero)
		container.addSubview(separator)
		container.snp.makeConstraints { $0.height.equalTo(25) }
		separator.snp.makeConstraints {
			$0.height.equalTo(1)
			$0.centerY.equalToSuperview()
			$0.leading.trailing.equalToSuperview().inset(MenuAnimation.horizontalInset)
		}
		return container
	}

	private func makeSectionTitle(_ title: String) -> UIView {
		let label = ThemeCSSLabel(frame: .zero)
		label.text = title
		label.font = .systemFont(ofSize: 13, weight: .semibold)
		label.snp.makeConstraints { $0.height.equalTo(32) }
		return label
	}

	// MARK: - Row interaction

	private func handleRowTap(entry: SidebarMenuEntry, accountController: AccountController?) {
		if entry.kind == .folder {
			toggleFolder(entry, accountController: accountController)
			return
		}

		if let accountController {
			focusedBookmark = accountController.bookmark
			registerFocusedBookmarkRevocation(for: accountController.bookmark)
			accountController.connect { [weak self] error in
				if let error, let bookmark = accountController.bookmark {
					let alert = ThemedAlertController(
						title: String(format: OCLocalizedString("Error opening %@", nil), bookmark.shortName),
						message: error.localizedDescription,
						preferredStyle: .alert
					)
					alert.addAction(UIAlertAction(title: OCLocalizedString("OK", nil), style: .default))
					self?.present(alert, animated: true)
					return
				}
				self?.open(entry.item, with: accountController.clientContext)
			}
		} else {
			open(entry.item, with: clientContext)
		}
	}

	private func open(_ item: OCDataItem, with context: ClientContext) {
		guard let interaction = item as? DataItemSelectionInteraction else { return }
		if interaction.handleSelection?(in: self, with: context, completion: { _, _ in }) == true { return }
		_ = interaction.openItem?(from: self, with: context, animated: true, pushViewController: true, completion: nil)
	}

	// MARK: - Highlight

	func applyHighlightState() {
		for (itemRef, row) in rowViewsByItemRef {
			row.isRowSelected = highlightedItemRefs.contains { $0.isEqual(itemRef) }
		}
	}

	// MARK: - Public selection API

	public func updateSelection(for navigationBookmark: BrowserNavigationBookmark?) {
		highlightedItemRefs = navigationBookmark?.representationSideBarItemRefs ?? []

		if let specialItem = navigationBookmark?.specialItem,
		   [.sharedWithMe, .sharedByMe, .sharedByLink].contains(specialItem),
		   let bookmarkUUID = navigationBookmark?.bookmarkUUID,
		   let accountController = dataModel.accountController(for: bookmarkUUID),
		   let sharingFolderRef = accountController.specialItemsDataReferences[.sharingFolder] {
			ensureFolderExpanded(sharingFolderRef, accountController: accountController)
		}

		applyHighlightState()
	}
}
