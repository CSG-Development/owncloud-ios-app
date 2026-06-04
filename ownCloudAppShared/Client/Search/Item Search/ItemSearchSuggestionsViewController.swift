//
//  ItemSearchSuggestionsViewController.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 08.09.22.
//  Copyright © 2022 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2022, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import ownCloudSDK
import ownCloudApp

extension OCQueryCondition {
	func matchesWith(anyOf searchElements: [SearchElement]) -> Bool {
		return searchElements.contains(where: { element in element.isEquivalent(to: self) })
	}
}

class SearchedContent: NSObject {
	var flags: OCKQLSearchedContent = []

	init(_ flags: OCKQLSearchedContent) {
		self.flags = flags
	}
}

private final class TagFilterMenuTableViewCell: UITableViewCell {
	static let reuseIdentifier = "TagFilterMenuTableViewCell"

	private let selectionIconView: UIImageView = {
		let imageView = UIImageView()
		imageView.contentMode = .scaleAspectFit
		imageView.setContentHuggingPriority(.required, for: .horizontal)
		imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
		return imageView
	}()

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: 16)
		label.lineBreakMode = .byTruncatingTail
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		return label
	}()

	private let tagIconView: UIImageView = {
		let imageView = UIImageView()
		imageView.contentMode = .scaleAspectFit
		imageView.setContentHuggingPriority(.required, for: .horizontal)
		imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
		return imageView
	}()

	private let separatorView = UIView()

	private let contentStack: UIStackView = {
		let stack = UIStackView()
		stack.axis = .horizontal
		stack.alignment = .center
		stack.spacing = 8
		stack.translatesAutoresizingMaskIntoConstraints = false
		return stack
	}()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)

		selectionStyle = .none
		backgroundColor = .clear
		contentView.backgroundColor = .clear
		backgroundConfiguration = UIBackgroundConfiguration.clear()

		contentStack.addArrangedSubview(selectionIconView)
		contentStack.addArrangedSubview(titleLabel)
		contentStack.addArrangedSubview(tagIconView)

		separatorView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(contentStack)
		contentView.addSubview(separatorView)

		NSLayoutConstraint.activate([
			selectionIconView.widthAnchor.constraint(equalToConstant: 24),
			selectionIconView.heightAnchor.constraint(equalToConstant: 24),
			tagIconView.widthAnchor.constraint(equalToConstant: 24),
			tagIconView.heightAnchor.constraint(equalToConstant: 24),

			contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
			contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
			contentStack.topAnchor.constraint(equalTo: contentView.topAnchor),
			contentStack.bottomAnchor.constraint(equalTo: separatorView.topAnchor),

			separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			separatorView.heightAnchor.constraint(equalToConstant: 1)
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(tag: OCSystemTag, isSelected: Bool, showsSeparator: Bool, isDark: Bool) {
		let primaryColor = HCColor.Content.textPrimary(isDark)

		titleLabel.text = tag.displayName
		titleLabel.textColor = primaryColor

		tagIconView.image = HCIcon.tagIcon?.withRenderingMode(.alwaysTemplate)
		tagIconView.tintColor = primaryColor

		selectionIconView.image = HCIcon.tick?.withRenderingMode(.alwaysTemplate)
		selectionIconView.tintColor = primaryColor
		selectionIconView.alpha = isSelected ? 1 : 0
		selectionIconView.isAccessibilityElement = false

		separatorView.backgroundColor = HCColor.Content.border2(isDark)
		separatorView.isHidden = !showsSeparator
	}
}

private final class TagFilterMenuViewController: UITableViewController {
	static let rowHeight: CGFloat = 44
	static let maxHeight: CGFloat = 300
	static let width: CGFloat = 280

	private let tags: [OCSystemTag]
	private var selectedTagIDs: Set<String>
	private let onToggle: (OCSystemTag, Bool) -> Void

	init(tags: [OCSystemTag], selectedTagIDs: Set<String>, onToggle: @escaping (OCSystemTag, Bool) -> Void) {
		self.tags = tags
		self.selectedTagIDs = selectedTagIDs
		self.onToggle = onToggle
		super.init(style: .plain)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private var isDarkMode: Bool {
		traitCollection.userInterfaceStyle == .dark
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.register(TagFilterMenuTableViewCell.self, forCellReuseIdentifier: TagFilterMenuTableViewCell.reuseIdentifier)
		tableView.separatorStyle = .none
		tableView.rowHeight = Self.rowHeight
		tableView.backgroundColor = .clear
		tableView.alwaysBounceVertical = tags.count * Int(Self.rowHeight) > Int(Self.maxHeight)
		updatePreferredContentSize()
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)

		if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
			tableView.reloadData()
		}
	}

	private func updatePreferredContentSize() {
		let rowCount = max(tags.count, 1)
		let contentHeight = min(Self.maxHeight, CGFloat(rowCount) * Self.rowHeight)
		preferredContentSize = CGSize(width: Self.width, height: contentHeight)
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		tags.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(
			withIdentifier: TagFilterMenuTableViewCell.reuseIdentifier,
			for: indexPath
		) as! TagFilterMenuTableViewCell

		let tag = tags[indexPath.row]
		cell.configure(
			tag: tag,
			isSelected: selectedTagIDs.contains(tag.identifier),
			showsSeparator: indexPath.row < tags.count - 1,
			isDark: isDarkMode
		)
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let tag = tags[indexPath.row]
		let wasSelected = selectedTagIDs.contains(tag.identifier)
		if wasSelected {
			selectedTagIDs.remove(tag.identifier)
		} else {
			selectedTagIDs.insert(tag.identifier)
		}
		onToggle(tag, wasSelected)
		tableView.reloadRows(at: [indexPath], with: .none)
	}
}

class ItemSearchSuggestionsViewController: UIViewController, SearchElementUpdating, UIPopoverPresentationControllerDelegate, Themeable {
	static let filterBarHeight: CGFloat = 56
	class Category {
		enum Identifier: String {
			case type
			case date
			case size
		}
		typealias SelectionBehaviour = (_ deselectOption: OCQueryCondition, _ whenOption: OCQueryCondition, _ isSelected: Bool) -> Bool

		static let mutuallyExclusiveSelectionBehaviour : SelectionBehaviour = { (deselectOption, whenOption, isSelected) in
			if isSelected, !deselectOption.isEquivalent(to: whenOption) {
				return true
			}

			return false
		}

		var name: String
		var id: Identifier
		var selectionBehaviour: SelectionBehaviour
		var options: [OCQueryCondition]

		var popupController: PopupButtonController?

		init(id: Identifier, name: String, selectionBehaviour: @escaping SelectionBehaviour, options: [OCQueryCondition]) {
			self.id = id
			self.name = name
			self.selectionBehaviour = selectionBehaviour
			self.options = options
		}

		func shouldDeselect(option optionCondition: OCQueryCondition, when otherOptionCondition: OCQueryCondition, isSelected: Bool) -> Bool {
			return selectionBehaviour(optionCondition, otherOptionCondition, isSelected)
		}
	}

	var categories: [Category] = [
		Category(id: .type, name: OCLocalizedString("Type", nil), selectionBehaviour: Category.mutuallyExclusiveSelectionBehaviour, options: [
			OCQueryCondition.fromSearchTerm(":file")!,
			OCQueryCondition.fromSearchTerm(":folder")!,
			OCQueryCondition.fromSearchTerm(":document")!,
			OCQueryCondition.fromSearchTerm(":spreadsheet")!,
			OCQueryCondition.fromSearchTerm(":presentation")!,
			OCQueryCondition.fromSearchTerm(":pdf")!,
			OCQueryCondition.fromSearchTerm(":image")!,
			OCQueryCondition.fromSearchTerm(":video")!,
			OCQueryCondition.fromSearchTerm(":audio")!,
			OCQueryCondition.fromSearchTerm(":archive")!
		]),
		Category(id: .date, name: OCLocalizedString("Date", nil), selectionBehaviour: Category.mutuallyExclusiveSelectionBehaviour, options: [
			OCQueryCondition.fromSearchTerm(":recent")!,
			OCQueryCondition.fromSearchTerm(":today")!,
			OCQueryCondition.fromSearchTerm(":week")!,
			OCQueryCondition.fromSearchTerm(":month")!,
			OCQueryCondition.fromSearchTerm(":year")!
		]),
		Category(id: .size, name: OCLocalizedString("Size", nil), selectionBehaviour: Category.mutuallyExclusiveSelectionBehaviour, options: [
			OCQueryCondition.fromSearchTerm("smaller:10mb")!,
			OCQueryCondition.fromSearchTerm("greater:10mb")!,
			OCQueryCondition.fromSearchTerm("smaller:100mb")!,
			OCQueryCondition.fromSearchTerm("greater:100mb")!,
			OCQueryCondition.fromSearchTerm("smaller:500mb")!,
			OCQueryCondition.fromSearchTerm("greater:500mb")!,
			OCQueryCondition.fromSearchTerm("smaller:1gb")!,
			OCQueryCondition.fromSearchTerm("greater:1gb")!
		])
	]

	lazy var stackView: UIStackView = {
		// Stack view
		let stackView = UIStackView(frame: .zero)
		stackView.translatesAutoresizingMaskIntoConstraints = false
		stackView.axis = .horizontal
		stackView.distribution = .fill
		stackView.alignment = .center
		stackView.spacing = 0
		return stackView
	}()

	var savedSearchPopup: PopupButtonController?
	var searchedContentPopup: PopupButtonController?
	private var tagsPopupController: PopupButtonController?
	private var tagSyncObserver: NSObjectProtocol?
	private var availableTags: [OCSystemTag] = []
	private var selectedTagIDs: Set<String> = []
	private var selectedTagNames: Set<String> = []
	private static let tagPropertyName = OCItemPropertyName(rawValue: "tag")

	weak var scope: SearchScope?

	init(with scope: SearchScope, excludeCategories: [Category.Identifier]? = nil) {
		super.init(nibName: nil, bundle: nil)
		categories = categories.filter({ category in
			if let excludeCategories {
				return !excludeCategories.contains(category.id)
			}
			return true
		})
		self.scope = scope
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		if let tagSyncObserver {
			NotificationCenter.default.removeObserver(tagSyncObserver)
		}
		Theme.shared.unregister(client: self)
	}

	private var didRegisterWithTheme = false

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if !didRegisterWithTheme {
			didRegisterWithTheme = true
			Theme.shared.register(client: self, applyImmediately: true)
		}

		ensureTagsFilterPopupIfNeeded()

		if scopeSupportsTagFiltering, let bookmark = scope?.clientContext.accountConnection?.bookmark ?? scope?.clientContext.core?.bookmark {
			AccountTagSyncService.shared.syncIfNeeded(for: bookmark, force: false)
			fetchAvailableTags()
		}
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		applyFilterChipStyleToPopupButtons()
	}

	func requestName(title: String, message: String? = nil, placeholder: String? = nil, cancelButtonText: String? = OCLocalizedString("Cancel", nil), saveButtonText: String? = OCLocalizedString("Save", nil), completionHandler: @escaping (_ save: Bool, _ name: String?) -> Void) {
		let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: saveButtonText, style: .default, handler: { [weak alert] _ in
			var text = alert?.textFields?.first?.text
			if text?.count == 0 { text = nil }
			completionHandler(true, text)
		}))
		alert.addAction(UIAlertAction(title: cancelButtonText, style: .cancel, handler: { _ in
			completionHandler(false, nil)
		}))
		alert.addTextField(configurationHandler: { textField in
			textField.placeholder = placeholder
		})

		self.present(alert, animated: true)
	}

	private var scopeSupportsContentSearch: Bool {
		scope?.searchableContent.contains(.contents) ?? false
	}

	private var scopeSupportsTagFiltering: Bool {
		(scope != nil) && ((scope is ItemSearchScope) || (scope?.tokenizer is CustomQuerySearchTokenizer))
	}

	private func ensureTagsFilterPopupIfNeeded() {
		guard scopeSupportsTagFiltering, tagsPopupController == nil else {
			return
		}

		createTagsPopup()

		let spacerIndex = stackView.arrangedSubviews.firstIndex(where: { $0 is HCSpacerView }) ?? stackView.arrangedSubviews.count
		if let button = tagsPopupController?.button {
			stackView.insertArrangedSubview(button, at: spacerIndex)
		}

		observeTagSyncIfNeeded()
		fetchAvailableTags()
	}

	private func createTagsPopup() {
		tagsPopupController = PopupButtonController(with: [], dropDown: true, staticTitle: OCLocalizedString("Tags", nil))

		if let button = tagsPopupController?.button {
			button.showsMenuAsPrimaryAction = false
			button.menu = nil
			button.addAction(UIAction { [weak self] _ in
				self?.presentTagsFilterMenu(from: button)
			}, for: .primaryActionTriggered)

			button.setContentCompressionResistancePriority(.required, for: .horizontal)
			button.setContentHuggingPriority(.required, for: .horizontal)
			style(popupButton: button, isSelected: tagsFilterIsActive())
		}
	}

	private func presentTagsFilterMenu(from sourceButton: UIButton) {
		loadCachedSystemTagsIfAvailable()
		fetchAvailableTags { [weak self] in
			guard let self else {
				return
			}

			var selectedIDs = self.selectedTagIDs
			for tag in self.availableTags where self.selectedTagNames.contains(tag.displayName) {
				selectedIDs.insert(tag.identifier)
			}

			let menuController = TagFilterMenuViewController(
				tags: self.availableTags,
				selectedTagIDs: selectedIDs,
				onToggle: { [weak self] tag, wasSelected in
					self?.handleTagSelection(tag, wasSelected: wasSelected)
				}
			)
			menuController.modalPresentationStyle = .popover
			if let popover = menuController.popoverPresentationController {
				sourceButton.layoutIfNeeded()
				popover.sourceView = sourceButton
				popover.sourceRect = sourceButton.bounds
				popover.permittedArrowDirections = [.up]
				popover.delegate = self
			}

			self.present(menuController, animated: true)
		}
	}

	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		.none
	}

	private func observeTagSyncIfNeeded() {
		guard tagSyncObserver == nil else {
			return
		}

		tagSyncObserver = NotificationCenter.default.addObserver(forName: .accountTagSyncDidFinish, object: nil, queue: .main) { [weak self] notification in
			self?.handleTagSyncDidFinish(notification)
		}
	}

	private func handleTagSyncDidFinish(_ notification: Notification) {
		guard scopeSupportsTagFiltering,
		      let bookmark = scope?.clientContext.accountConnection?.bookmark ?? scope?.clientContext.core?.bookmark,
		      let syncedBookmark = notification.userInfo?[AccountTagSyncService.bookmarkUserInfoKey] as? OCBookmark,
		      syncedBookmark.uuid == bookmark.uuid else {
			return
		}

		loadCachedSystemTagsIfAvailable()
		updateTagsPopupStyle()
		refreshActiveSearchForTagChangesIfNeeded()
	}

	private func refreshActiveSearchForTagChangesIfNeeded() {
		guard !selectedTagIDs.isEmpty || !selectedTagNames.isEmpty else {
			return
		}

		if let customScope = scope as? CustomQuerySearchScope {
			customScope.updateCustomSearchQuery()
		} else {
			scope?.updateFor(searchElements)
		}
	}

	private func handleTagSelection(_ tag: OCSystemTag, wasSelected: Bool) {
		var selectedTags = currentlySelectedTags()

		if wasSelected {
			selectedTags.removeAll { $0.identifier == tag.identifier }
		} else if !selectedTags.contains(where: { $0.identifier == tag.identifier }) {
			selectedTags.append(tag)
		}

		applyTagSelection(selectedTags)
	}

	private func currentlySelectedTags() -> [OCSystemTag] {
		availableTags.filter { tag in
			selectedTagIDs.contains(tag.identifier) || selectedTagNames.contains(tag.displayName)
		}
	}

	override func viewDidLoad() {
		// Saved search popup
		savedSearchPopup = PopupButtonController(with: [], selectFirstChoice: false, dropDown: true, choiceHandler: { [weak self] choice, wasSelected in
			if let scope = self?.scope, let command = choice.representedObject as? String {
				switch command {
					case "save-search":
						if let savedSearch = scope.savedSearch as? OCSavedSearch, let vault = scope.clientContext.core?.vault {
							OnMainThread {
								self?.requestName(title: OCLocalizedString("Name of saved search", nil), placeholder: OCLocalizedString("Saved search", nil), completionHandler: { save, name in
									if save {
										if let name = name {
											savedSearch.name = name
										}
										vault.add(savedSearch)
									}
								})
							}
						}
					case "save-template":
						if let savedSearch = scope.savedTemplate as? OCSavedSearch, let vault = scope.clientContext.core?.vault {
							OnMainThread {
								self?.requestName(title: OCLocalizedString("Name of template", nil), placeholder: OCLocalizedString("Search template", nil), completionHandler: { save, name in
									if save {
										if let name = name {
											savedSearch.name = name
										}
										vault.add(savedSearch)
									}
								})
							}
						}

					default: break
				}
			} else if let savedSearch = choice.representedObject as? OCSavedSearch {
				self?.restore(savedSearch: savedSearch)
			}
		})
		savedSearchPopup?.choicesProvider = { [weak self] (_ popupController: PopupButtonController) in
			var choices: [PopupButtonChoice] = []

			if (self?.scope as? ItemSearchScope)?.canSaveSearch == true {
				let saveSearchChoice = PopupButtonChoice(with: OCLocalizedString("Save search", nil), image: OCSymbol.icon(forSymbolName: "folder.badge.gearshape"), representedObject: NSString("save-search"))
				choices.append(saveSearchChoice)
			}

			if (self?.scope as? ItemSearchScope)?.canSaveTemplate == true {
				let saveTemplateChoice = PopupButtonChoice(with: OCLocalizedString("Save as search template", nil), image: OCSymbol.icon(forSymbolName: "plus.square.dashed"), representedObject: NSString("save-template"))
				choices.append(saveTemplateChoice)
			}

			return choices
		}

		var buttonConfiguration = UIButton.Configuration.plain().updated(for: savedSearchPopup!.button)
		buttonConfiguration.image = OCSymbol.icon(forSymbolName: "ellipsis.circle")
		buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 5, bottom: 10, trailing: 5)
		buttonConfiguration.attributedTitle = nil
		savedSearchPopup?.adaptButton = false
		savedSearchPopup?.button.setAttributedTitle(nil, for: .normal)
		savedSearchPopup?.button.configuration = buttonConfiguration

		// Searched content popup
		let fileNameOnlyChoice = PopupButtonChoice(with: OCLocalizedString("names", ""), image: nil, representedObject: SearchedContent(.itemName))
		let contentsOnlyChoice = PopupButtonChoice(with: OCLocalizedString("contents", ""), image: nil, representedObject: SearchedContent(.contents))
		let fileNameAndContentsChoice = PopupButtonChoice(with: OCLocalizedString("name + contents", ""), image: nil, representedObject: SearchedContent([.contents, .itemName]))

		searchedContentPopup = PopupButtonController(with: [], dropDown: false, selectionCustomizer: { [weak self] (choice, isSelected) in
			if let scope = self?.scope, let searchedContent = choice.representedObject as? SearchedContent {
				return scope.searchedContent == searchedContent.flags
			}
			return isSelected
		}, choiceHandler: { [weak self] (choice, wasSelected) in
			if let scope = self?.scope, let searchedContent = choice.representedObject as? SearchedContent {
				scope.searchedContent = searchedContent.flags
			}
		})
		searchedContentPopup?.choicesProvider = { [weak self] (_ popupController: PopupButtonController) in
			var choices: [PopupButtonChoice] = []

			if let scope = self?.scope {
				if scope.searchableContent.contains(.itemName) {
					choices.append(fileNameOnlyChoice)
				}
				if scope.searchableContent.contains(.contents) {
					choices.append(contentsOnlyChoice)
				}
				if scope.searchableContent.contains(.itemName) && scope.searchableContent.contains(.contents) {
					choices.append(fileNameAndContentsChoice)
				}
			}

			return choices
		}
		if let searchedContent = scope?.searchedContent {
			switch searchedContent {
				case .contents: searchedContentPopup?.selectedChoice = contentsOnlyChoice
				case .itemName: searchedContentPopup?.selectedChoice = fileNameOnlyChoice
				default: searchedContentPopup?.selectedChoice = fileNameAndContentsChoice
			}
		}

		preferredContentSize = CGSize(width: UIView.noIntrinsicMetric, height: Self.filterBarHeight)

		view.addSubview(stackView)

		NSLayoutConstraint.activate([
			view.heightAnchor.constraint(equalToConstant: Self.filterBarHeight),
			stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			stackView.topAnchor.constraint(equalTo: view.topAnchor),
			stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])

		createPopups()
		applyFilterChipStyleToPopupButtons()

		stackView.isLayoutMarginsRelativeArrangement = true

		for category in categories {
			if let button = category.popupController?.button {
				button.setContentCompressionResistancePriority(.required, for: .horizontal)
				stackView.addArrangedSubview(button)
			}
		}
		ensureTagsFilterPopupIfNeeded()
		let spacerView = HCSpacerView(nil, .horizontal)
		spacerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		stackView.addArrangedSubview(spacerView)

		if let button = savedSearchPopup?.button {
			stackView.addArrangedSubview(button)
		}
		if scopeSupportsContentSearch, let searchedContentPopup {
			let containerView = UIView()
			containerView.translatesAutoresizingMaskIntoConstraints = false

			let popupButton = searchedContentPopup.button
			let searchInLabel = UILabel()
			searchInLabel.text = OCLocalizedString("Search in", nil)
			searchInLabel.translatesAutoresizingMaskIntoConstraints = false

			style(popupButton: popupButton, isSelected: false)

			containerView.addSubview(searchInLabel)
			containerView.addSubview(popupButton)

			popupButton.setContentCompressionResistancePriority(.required, for: .horizontal)
			popupButton.setContentHuggingPriority(.required, for: .horizontal)

			NSLayoutConstraint.activate([
				searchInLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
				popupButton.leadingAnchor.constraint(equalTo: searchInLabel.trailingAnchor, constant: 2),
				popupButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

				searchInLabel.firstBaselineAnchor.constraint(equalTo: popupButton.titleLabel!.firstBaselineAnchor),
				popupButton.topAnchor.constraint(equalTo: containerView.topAnchor),
				popupButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
			])

			stackView.addArrangedSubview(containerView)
		}
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)

		if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
			applyFilterChipStyleToPopupButtons()
		}

		// Fix for the wrong stack view layout after rotation from landscape with opened sidebar.
		DispatchQueue.main.async {
			self.stackView.arrangedSubviews.forEach {
				$0.invalidateIntrinsicContentSize()
			}
		}
	}

	func createPopups() {
		// Create popups for all categories
		for category in categories {
			var choices : [PopupButtonChoice] = []

			for queryCondition in category.options {
				if let localizedDescription = queryCondition.localizedDescription {
					let choice = PopupButtonChoice(with: localizedDescription, image: OCSymbol.icon(forSymbolName: queryCondition.symbolName), representedObject: queryCondition)
					choices.append(choice)
				}
			}

			let popupController = PopupButtonController(with: choices, dropDown: true, staticTitle: category.name, selectionCustomizer: { [weak self] (choice, isSelected) in
				if let queryCondition = choice.representedObject as? OCQueryCondition, let searchElements = self?.searchElements {
					return queryCondition.matchesWith(anyOf: searchElements)
				}
				return isSelected
			}, choiceHandler: { [weak self, weak category] (choice, wasSelected) in
				if let category = category, let queryCondition = choice.representedObject as? OCQueryCondition {
					self?.handleSelection(of: queryCondition, in: category, wasSelected: wasSelected)
				}
			})

			let button = popupController.button
			button.setContentCompressionResistancePriority(.required, for: .horizontal)
			button.setContentHuggingPriority(.required, for: .horizontal)

			category.popupController = popupController
		}
	}

	var searchElements: [SearchElement] = []

	private func loadCachedSystemTagsIfAvailable() {
		guard let bookmark = scope?.clientContext.accountConnection?.bookmark else {
			return
		}
		if let cachedTags = AccountTagSyncService.shared.cachedSystemTags(for: bookmark) {
			mergeAvailableTags(with: cachedTags)
			syncSelectedTagNamesFromSearchElements()
		}
	}

	private func fetchAvailableTags(completion: (() -> Void)? = nil) {
		guard scopeSupportsTagFiltering, let connection = scope?.clientContext.core?.connection else {
			completion?()
			return
		}

		loadCachedSystemTagsIfAvailable()

		let bookmark = scope?.clientContext.accountConnection?.bookmark
		let shouldFetchFromServer = availableTags.isEmpty || bookmark.map { AccountTagSyncService.shared.shouldSync(bookmark: $0) } ?? true
		guard shouldFetchFromServer else {
			completion?()
			return
		}

		connection.retrieveSystemTags { [weak self] error, tags in
			OnMainThread {
				guard let self = self else {
					completion?()
					return
				}
				if error == nil {
					let visibleTags = (tags ?? []).filter(\.userVisible)
					self.mergeAvailableTags(with: visibleTags)
					self.syncSelectedTagNamesFromSearchElements()
					if let bookmark {
						AccountTagSyncService.shared.updateCachedSystemTags(visibleTags, for: bookmark)
						AccountTagSyncService.shared.syncIfNeeded(for: bookmark, force: false)
					}
				}
				completion?()
			}
		}
	}

	private func mergeAvailableTags(with incomingTags: [OCSystemTag]) {
		guard !incomingTags.isEmpty else {
			return
		}

		var mergedByDisplayName: [String: OCSystemTag] = [:]

		for tag in availableTags {
			let key = tag.displayName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
			mergedByDisplayName[key] = tag
		}

		for tag in incomingTags {
			let key = tag.displayName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
			if let existingTag = mergedByDisplayName[key] {
				if existingTag.identifier.hasPrefix("local:") && !tag.identifier.hasPrefix("local:") {
					mergedByDisplayName[key] = tag
				}
			} else {
				mergedByDisplayName[key] = tag
			}
		}

		availableTags = Array(mergedByDisplayName.values).sorted {
			$0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
		}
		updateTagsPopupStyle()
	}

	private func applyTagSelection(_ selectedTags: [OCSystemTag]) {
		let serverTags = selectedTags.filter { !$0.identifier.hasPrefix("local:") }
		selectedTagIDs = Set(serverTags.map(\.identifier))
		selectedTagNames = Set(serverTags.map(\.displayName))

		guard let tokenizer = scope?.tokenizer, let searchField = tokenizer.searchField else {
			updateTagsPopupStyle()
			return
		}

		for tokenIndex in stride(from: searchField.tokens.count - 1, through: 0, by: -1) {
			let token = searchField.tokens[tokenIndex]
			if let searchToken = token.representedObject as? SearchToken,
			   (searchToken.representedObject is SearchTagFilter ||
				((searchToken.representedObject as? OCQueryCondition).map(Self.isTagCondition) ?? false)) {
					searchField.removeToken(at: tokenIndex)
			}
		}

		for selectedTag in serverTags {
			if scope is ServerSideSearchScope {
				let condition = Self.makeTagCondition(from: selectedTag.displayName)
				if let token = condition.generateSearchToken(fallbackText: selectedTag.displayName, inputComplete: true) {
					searchField.insertToken(token.uiSearchToken, at: searchField.tokens.count)
				}
			} else {
				let tagToken = SearchToken(
					text: selectedTag.displayName,
					icon: HCIcon.tagIcon,
					representedObject: SearchTagFilter(tagID: selectedTag.identifier, tagName: selectedTag.displayName),
					inputComplete: true
				)
				searchField.insertToken(tagToken.uiSearchToken, at: searchField.tokens.count)
			}
		}

		tokenizer.updateFor(searchField: searchField)
		updateTagsPopupStyle()

		guard let bookmark = scope?.clientContext.accountConnection?.bookmark ?? scope?.clientContext.core?.bookmark else {
			return
		}

		if selectedTagIDs.isEmpty && selectedTagNames.isEmpty {
			return
		}

		let knownTags = serverTags
		AccountTagSyncService.shared.refreshTags(
			selection: selectedTagIDs,
			tagNames: selectedTagNames,
			knownTags: knownTags,
			bookmark: bookmark
		) { [weak self] in
			guard let self, self.scope?.isSelected == true else { return }
			if let customScope = self.scope as? CustomQuerySearchScope {
				customScope.updateCustomSearchQuery()
			} else {
				self.scope?.updateFor(self.searchElements)
			}
		}
	}

	private static func makeTagCondition(from tagName: String) -> OCQueryCondition {
		let condition = OCQueryCondition.where(Self.tagPropertyName, isEqualTo: tagName)
		condition.symbolName = "tag"
		condition.localizedDescription = tagName
		return condition
	}

	private static func isTagCondition(_ condition: OCQueryCondition) -> Bool {
		condition.isTagSearchCondition
	}

	private func syncSelectedTagNamesFromSearchElements() {
		selectedTagIDs = Set(searchElements.compactMap({ searchElement in
			if let tagFilter = searchElement.representedObject as? SearchTagFilter,
			   let tagID = tagFilter.tagID,
			   !tagID.hasPrefix("local:") {
				return tagID
			}
			return nil
		}))

		selectedTagNames = Set(searchElements.compactMap({ searchElement in
			if let tagFilter = searchElement.representedObject as? SearchTagFilter {
				return tagFilter.tagName
			}

			guard let condition = searchElement.representedObject as? OCQueryCondition,
			      Self.isTagCondition(condition),
			      let tagName = condition.value as? String else {
				return nil
			}
			return tagName
		}))

		for tagName in selectedTagNames {
			if let matchingTag = availableTags.first(where: {
				$0.displayName.compare(tagName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
				&& !$0.identifier.hasPrefix("local:")
			}) {
				selectedTagIDs.insert(matchingTag.identifier)
			}
		}

		updateTagsPopupStyle()
	}

	private func updateTagsPopupStyle() {
		guard let tagsPopupButton = tagsPopupController?.button else {
			return
		}

		style(popupButton: tagsPopupButton, isSelected: tagsFilterIsActive())
		tagsPopupButton.sizeToFit()
	}

	func handleSelection(of selectedOptionCondition: OCQueryCondition, in category: Category, wasSelected: Bool) {
		var removeOptionConditions : [OCQueryCondition] = []
		var addOptionConditions : [OCQueryCondition] = []

		// Determine whether / if any other options should be removed (f.ex. to implement mutually exclusive choices)
		for option in category.options {
			if category.shouldDeselect(option: option, when: selectedOptionCondition, isSelected: !wasSelected) {
				removeOptionConditions.append(option)
			}
		}

		if !wasSelected {
			// Option was freshly selected
			addOptionConditions.append(selectedOptionCondition)
		} else {
			// Option was deselected
			removeOptionConditions.append(selectedOptionCondition)
		}

		for removeOptionToken in removeOptionConditions {
			scope?.tokenizer?.remove(elementEquivalentTo: removeOptionToken)
		}

		for addOptionToken in addOptionConditions {
			if let searchToken = addOptionToken.generateSearchToken(fallbackText: "", inputComplete: true) {
				scope?.tokenizer?.add(element: searchToken)
			}
		}
	}

	func restore(savedSearch: OCSavedSearch) {
		scope?.searchViewController?.restore(savedTemplate: savedSearch)
	}

	private var isFilterChipDarkMode: Bool {
		traitCollection.userInterfaceStyle == .dark
	}

	private func tagsFilterIsActive() -> Bool {
		!selectedTagIDs.isEmpty || !selectedTagNames.isEmpty
	}

	private func categoryHasActiveFilter(_ category: Category) -> Bool {
		category.options.contains { $0.matchesWith(anyOf: searchElements) }
	}

	private func applyFilterChipStyleToPopupButtons() {
		for category in categories {
			if let button = category.popupController?.button {
				style(popupButton: button, isSelected: categoryHasActiveFilter(category))
			}
		}

		if let tagsButton = tagsPopupController?.button {
			style(popupButton: tagsButton, isSelected: tagsFilterIsActive())
		}
	}

	private func style(popupButton: UIButton, isSelected: Bool) {
		let isDark = isFilterChipDarkMode
		let primaryColor = HCColor.Interaction.primarySolidNormal(isDark)
		let legacyTitle = popupButton.currentAttributedTitle
			?? popupButton.configuration?.attributedTitle.map(NSAttributedString.init)

		// Legacy titles prevent UIButton.Configuration backgrounds from rendering.
		popupButton.setAttributedTitle(nil, for: .normal)

		var buttonConfig = SearchFilterChipStyle.filterBarButtonConfiguration(isDark: isDark, isSelected: isSelected)

		if let legacyTitle {
			let title = NSMutableAttributedString(attributedString: legacyTitle)
			title.addAttribute(
				.foregroundColor,
				value: primaryColor,
				range: NSRange(location: 0, length: title.length)
			)
			buttonConfig.attributedTitle = AttributedString(title)
		}

		popupButton.configuration = buttonConfig
		popupButton.tintColor = primaryColor
		SearchFilterChipStyle.applyFilterBarButtonHeight(to: popupButton)

		popupButton.configurationUpdateHandler = { [isDark] button in
			guard var config = button.configuration else { return }

			let selectedBackground = HCColor.Interaction.primaryTransparentNormal12(isDark)
			if isSelected {
				config.baseBackgroundColor = selectedBackground
				config.background.backgroundColor = selectedBackground
				config.background.cornerRadius = 1000
				config.cornerStyle = .capsule
			} else {
				config.baseBackgroundColor = .clear
				config.background.backgroundColor = .clear
			}

			button.configuration = config
		}
	}

	func updateFor(_ searchElements: [SearchElement]) {
		self.searchElements = searchElements
		ensureTagsFilterPopupIfNeeded()
		if scopeSupportsTagFiltering {
			syncSelectedTagNamesFromSearchElements()
		}

		// Hide saved search popup button
		var showSavedSearchButton : Bool = false
		if let searchScope = scope as? ItemSearchScope, searchScope.canSaveSearch || searchScope.canSaveTemplate {
			showSavedSearchButton = true
		}
		savedSearchPopup?.button.isHidden = !showSavedSearchButton

		for category in categories {
			if let categoryPopupButton = category.popupController?.button {
				style(popupButton: categoryPopupButton, isSelected: categoryHasActiveFilter(category))
				categoryPopupButton.sizeToFit()
			}
		}

		if scopeSupportsTagFiltering {
			updateTagsPopupStyle()
		}
	}
}
