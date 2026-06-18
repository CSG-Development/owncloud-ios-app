//
//  SearchViewController.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 21.06.22.
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

public protocol SearchViewControllerDelegate: AnyObject {
	func searchBegan(for viewController: SearchViewController)
	func search(for viewController: SearchViewController, content: SearchViewController.Content?)
	func searchEnded(for viewController: SearchViewController)
}

public protocol SearchElementUpdating: AnyObject {
	func updateFor(_ searchElements: [SearchElement])
}

public protocol SearchViewControllerHost: AnyObject {
	var searchViewController: SearchViewController? { get }
}

open class SearchViewController: UIViewController, UITextFieldDelegate, Themeable {
	private var resultsSourceObservation: NSKeyValueObservation?
	private var resultsCellStyleObservation: NSKeyValueObservation?
	private weak var cancelToolbarButton: UIBarButtonItem?
	private weak var clearButton: UIButton?
	private var recipientSearchWaitingObservation: NSKeyValueObservation?

	open var clientContext: ClientContext

	open weak var delegate: SearchViewControllerDelegate?

	open var scopes: [SearchScope]? {
		didSet {
			updateChoicesFromScopes()
		}
	}

	open var activeScope: SearchScope? {
		willSet {
			if activeScope != newValue {
				activeScope?.tokenizer?.searchField = nil
				activeScope?.searchViewController = nil
				activeScope?.isSelected = false

				resultsSourceObservation?.invalidate()
				resultsSourceObservation = nil

				resultsCellStyleObservation?.invalidate()
				resultsCellStyleObservation = nil

				recipientSearchWaitingObservation?.invalidate()
				recipientSearchWaitingObservation = nil
			}
		}

		didSet {
			if let activeScope = activeScope, let activeScopeChoice = self.scopePopup?.choices?.first(where: { choice in
				(choice.representedObject as? NSObject) == activeScope
			}) {
				OnMainThread {
					self.scopePopup?.selectedChoice = activeScopeChoice
				}
			}

			if activeScope != oldValue {
				activeScope?.tokenizer?.searchField = searchField
				activeScope?.isSelected = true
				activeScope?.searchViewController = self

				resultsSourceObservation = activeScope?.observe(\.results, options: .initial, changeHandler: { [weak self] (scope, change) in
					if let self = self {
						self.updateScopeSearchResults(from: self.activeScope?.results, with: self.activeScope?.resultsCellStyle)
					}
				})

				resultsCellStyleObservation = activeScope?.observe(\.resultsCellStyle, changeHandler: { [weak self] (scope, change) in
					if let self = self {
						self.updateScopeSearchResults(from: self.activeScope?.results, with: self.activeScope?.resultsCellStyle)
					}
				})

				searchField.placeholder = activeScope?.localizedPlaceholder

				scopeViewController = activeScope?.scopeViewController

				if let recipientScope = activeScope as? RecipientSearchScope {
					recipientSearchWaitingObservation = recipientScope.recipientSearchController?.observe(\.isWaitingForResults, options: [.initial, .new]) { [weak self] _, _ in
						self?.updateCurrentContent()
					}
				}

				sendSearchFieldContentsToActiveScope()
			}
		}
	}

	private func updateChoicesFromScopes() {
		var choices : [PopupButtonChoice] = []

		if let scopes = scopes {
			for scope in scopes {
				choices.append(PopupButtonChoice(with: scope.localizedName, image: scope.icon, representedObject: scope))
			}
		}

		let previouslySelectedChoice = scopePopup?.selectedChoice

		scopePopup?.choices = choices

		if let previouslySelectedChoice = previouslySelectedChoice, let previouslyRepresentedObject = previouslySelectedChoice.representedObject as? NSObject, let equalSelectedChoice = choices.first(where: { choice in
			if let representedObject = choice.representedObject as? NSObject {
				return representedObject == previouslyRepresentedObject
			}

			return false
		}) {
			scopePopup?.selectedChoice = equalSelectedChoice
		}
	}

	private var _defaultScope: SearchScope?

	init(with clientContext: ClientContext, scopes: [SearchScope]?, defaultScope: SearchScope? = nil, targetNavigationItem: UINavigationItem? = nil, suggestionContent: Content? = nil, noResultContent: Content? = nil, delegate: SearchViewControllerDelegate?, showCancelButton: Bool = true, hideNavigationButtons: Bool = true) {
		self.clientContext = clientContext

		super.init(nibName: nil, bundle: nil)

		self.showCancelButton = showCancelButton
		self.hideNavigationButtons = hideNavigationButtons
		self.targetNavigationItem = targetNavigationItem ?? clientContext.originatingViewController?.navigationItem

		self.suggestionContent = suggestionContent
		self.noResultContent = noResultContent

		self.delegate = delegate

		self.scopes = scopes
		self._defaultScope = defaultScope

		updateCurrentContent()
	}

	required public init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		Theme.shared.unregister(client: self)
	}

	// MARK: - Views
	private static let searchFieldContainerHeight: CGFloat = 36

	var searchField: UISearchTextField = UISearchTextField()
	var searchContainerView: UIView = UIView()
	var scopePopup: PopupButtonController?
	var scopeViewController: UIViewController? {
		willSet {
			scopeViewController?.willMove(toParent: nil)
			scopeViewController?.view.removeFromSuperview()
			scopeViewController?.removeFromParent()

			scopeViewControllerConstraints = nil
		}
		didSet {
			if let scopeViewController = scopeViewController, let scopeViewControllerView = scopeViewController.view {
				addChild(scopeViewController)
				view.addSubview(scopeViewControllerView)
				scopeViewControllerView.translatesAutoresizingMaskIntoConstraints = false

				let horizontalInset: CGFloat = 15
				let topInset: CGFloat = 0
				let bottomInset: CGFloat = 0
				let anchors = view.safeAreaAnchorSet

				if scopeViewController is ItemSearchSuggestionsViewController {
					let filterBarHeight = ItemSearchSuggestionsViewController.filterBarHeight
					scopeViewControllerConstraints = [
						scopeViewControllerView.leadingAnchor.constraint(equalTo: anchors.leadingAnchor, constant: horizontalInset),
						scopeViewControllerView.trailingAnchor.constraint(equalTo: anchors.trailingAnchor, constant: -horizontalInset),
						scopeViewControllerView.topAnchor.constraint(equalTo: anchors.topAnchor, constant: topInset),
						scopeViewControllerView.heightAnchor.constraint(equalToConstant: filterBarHeight),
						view.bottomAnchor.constraint(equalTo: scopeViewControllerView.bottomAnchor, constant: bottomInset)
					]
				} else {
					scopeViewControllerConstraints = view.embed(
						toFillWith: scopeViewControllerView,
						insets: NSDirectionalEdgeInsets(top: topInset, leading: horizontalInset, bottom: bottomInset, trailing: horizontalInset),
						enclosingAnchors: anchors
					)
				}

				NSLayoutConstraint.activate(scopeViewControllerConstraints ?? [])
				scopeViewController.didMove(toParent: self)
			}
		}
	}
	private var scopeViewControllerConstraints : [NSLayoutConstraint]?

	open override func loadView() {
		let rootView = ThemeCSSView(withSelectors: [.searchSuggestions])

		scopePopup = PopupButtonController(with: [], selectedChoice: nil, choiceHandler: { [weak self] (choice, _) in
			self?.activeScope = choice.representedObject as? SearchScope
		})

		var scopePopupButtonConfiguration = UIButton.Configuration.borderless()
		scopePopupButtonConfiguration.contentInsets.leading = 0
		scopePopupButtonConfiguration.contentInsets.trailing = 5
		scopePopup?.button.configuration = scopePopupButtonConfiguration

		NSLayoutConstraint.activate([
			rootView.heightAnchor.constraint(equalToConstant: 0).with(priority: .defaultHigh), // Shrink to 10 points height if no scopeViewController is set
			searchContainerView.widthAnchor.constraint(equalToConstant: 10000).with(priority: .defaultHigh) // maximize width of container in UINavigationBar
		])

		view = rootView
	}

	open override func viewDidLoad() {
		super.viewDidLoad()

		searchField.translatesAutoresizingMaskIntoConstraints = false
		searchField.addTarget(self, action: #selector(searchFieldContentsChanged), for: .editingChanged)
		searchField.delegate = self
		// Ensure the text field itself has no background; we render background in the container
		searchField.backgroundColor = .clear
		searchField.borderStyle = .none

		// Prepare container for background and vertical padding in navigation bar
		searchContainerView.translatesAutoresizingMaskIntoConstraints = false
		searchContainerView.addSubview(searchField)
		NSLayoutConstraint.activate([
			searchField.leadingAnchor.constraint(equalTo: searchContainerView.leadingAnchor),
			searchField.trailingAnchor.constraint(equalTo: searchContainerView.trailingAnchor),
			searchField.topAnchor.constraint(equalTo: searchContainerView.topAnchor),
			searchField.bottomAnchor.constraint(equalTo: searchContainerView.bottomAnchor),
			searchContainerView.heightAnchor.constraint(equalToConstant: Self.searchFieldContainerHeight)
		])

		searchContainerView.layer.cornerRadius = Self.searchFieldContainerHeight / 2
		searchContainerView.layer.masksToBounds = true

		if let scopesCount = scopes?.count, scopesCount > 1 {
			searchField.leftView = scopePopup?.button
		}

		injectIntoNavigationItem()

		updateChoicesFromScopes()

		delegate?.searchBegan(for: self)

		if activeScope == nil {
			activeScope = scopes?.first
		}

		searchField.clearButtonMode = .never

		var cfg = UIButton.Configuration.plain()
		cfg.image = UIImage(systemName: "xmark.circle.fill")
		cfg.preferredSymbolConfigurationForImage = .init(pointSize: 12, weight: .regular)
		cfg.contentInsets = .init(top: 10, leading: 8, bottom: 10, trailing: 0)

		let clearButton = UIButton(configuration: cfg)

		self.clearButton = clearButton
		clearButton.addTarget(self, action: #selector(clearTextField), for: .touchUpInside)
		searchField.rightView = clearButton
		searchField.rightViewMode = .never
		searchField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
		searchField.addTarget(self, action: #selector(editingDidBegin), for: .editingDidBegin)
		searchField.addTarget(self, action: #selector(editingDidEnd), for: .editingDidEnd)
	}

	private func updateTextField() {
		let isEmpty = searchField.text?.isEmpty ?? true
		let isFirstResponder = searchField.isFirstResponder
		searchField.rightViewMode = !isEmpty && isFirstResponder ? .always : .never
	}

	@objc private func clearTextField() {
		searchField.text = nil
		updateTextField()
	}

	@objc private func editingChanged() {
		updateTextField()
	}

	@objc private func editingDidBegin() {
		updateTextField()
	}

	@objc private func editingDidEnd() {
		updateTextField()
	}

	private var _registered = false
	open override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		if !_registered {
			_registered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}

		if let _defaultScope {
			activeScope = _defaultScope
			self._defaultScope = nil // Set default scope only once
		}
	}

	open override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		OnMainThread {
			self.searchField.becomeFirstResponder()
		}
	}

	// MARK: - Navigation item modification
	open var showCancelButton: Bool = true
	open var hideNavigationButtons: Bool = true

	var targetNavigationItem: UINavigationItem?

	var niInjected: Bool = false
	var niHidesBackButton: Bool = false

	func injectIntoNavigationItem() {
		if !niInjected, let targetNavigationItem {
			var navigationContentItems: [NavigationContentItem] = []

			// Store content
			niHidesBackButton = targetNavigationItem.hidesBackButton

			// Compose navigation views
			// - "Overwrite" <> navigation buttons with no content
			if hideNavigationButtons {
				navigationContentItems.append(NavigationContentItem(identifier: "search-left", area: .left, priority: .highest, position: .trailing, items: [ ]))
			}

			// - add search field (container provides background + 8pt vertical padding)
			navigationContentItems.append(NavigationContentItem(identifier: "search-field", area: .title, priority: .highest, position: .leading, titleView: searchContainerView))

			// - add X (cancel) button
			if showCancelButton {
				// Alternative implementation as a standard "Cancel" button, more convention compliant, but needs more space: let cancelToolbarButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(endSearch))
				let cancelToolbarButton = UIBarButtonItem(image: OCSymbol.icon(forSymbolName: "xmark"), style: .done, target: self, action: #selector(endSearch))
				navigationContentItems.append(NavigationContentItem(identifier: "search-right", area: .right, priority: .highest, position: .trailing, items: [ cancelToolbarButton ]))
				self.cancelToolbarButton = cancelToolbarButton
			}

			// Overwrite content
			targetNavigationItem.navigationContent.add(items: navigationContentItems)
			targetNavigationItem.hidesBackButton = true

			niInjected = true
		}
	}

	func restoreNavigationItem() {
		if niInjected, let targetNavigationItem {
			// Restore content
			targetNavigationItem.navigationContent.remove(itemsWithIdentifiers: [
				"search-left",
				"search-field",
				"search-right"
			])
			targetNavigationItem.hidesBackButton = niHidesBackButton
			niInjected = false
		}
	}

	// MARK: - Input handling
	public func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
		return true
	}

	private func applyFilterChipStyleToSearchTokens() {
		searchField.applyFilterChipAppearance(isDark: traitCollection.userInterfaceStyle == .dark)
	}

	@objc func searchFieldContentsChanged() {
		sendSearchFieldContentsToActiveScope()
		updateCurrentContent()
	}

	func sendSearchFieldContentsToActiveScope() {
		self.activeScope?.tokenizer?.updateFor(searchField: searchField)
		applyFilterChipStyleToSearchTokens()
	}

	// MARK: - Search results
	// Content
	public enum ContentType {
		case suggestion
		case noResults
		case results
	}

	public struct Content: Equatable {
		var type: ContentType
		var source: OCDataSource?
		var style: CollectionViewCellStyle?
	}

	open var suggestionContent: Content? {
		didSet {
			updateCurrentContent()
		}
	}
	open var noResultContent: Content? {
		didSet {
			updateCurrentContent()
		}
	}
	open var resultContent: Content? {
		didSet {
			updateCurrentContent()
		}
	}

	// Keeping track of scope's results and cell style
	open var scopeResults: OCDataSource? {
		willSet {
			if newValue != scopeResults {
				scopeResultsSubscription?.terminate()
				scopeResultsSubscription = nil
			}
		}

		didSet {
			if oldValue != scopeResults {
				scopeResultsSubscription = scopeResults?.subscribe(updateHandler: { [weak self] (subscription) in
					let snapshot = subscription.snapshotResettingChangeTracking(true)
					var itemCount: UInt = 0

					for itemRef in snapshot.items {
						if let record = try? subscription.source?.record(forItemRef: itemRef),
						   record.item is OCItem || record.item is OCIdentity {
							itemCount += 1
						}
					}

					self?.scopeResultsItemCount = itemCount
				}, on: .main, trackDifferences: false, performInitialUpdate: true)
			}
		}
	}
	var scopeResultsSubscription: OCDataSourceSubscription?
	var scopeResultsItemCount: UInt = 0 {
		didSet {
			updateCurrentContent()
		}
	}

	private var scopeResultsAreLoading: Bool {
		if let recipientScope = activeScope as? RecipientSearchScope {
			return recipientScope.recipientSearchController?.isWaitingForResults ?? false
		}

		guard let customScope = activeScope as? CustomQuerySearchScope,
		      let queryState = customScope.customQuery?.state else {
			return false
		}

		switch queryState {
			case .started, .waitingForServerReply:
				return true
			default:
				return false
		}
	}
	open var scopeResultsCellStyle: CollectionViewCellStyle?

	open func updateScopeSearchResults(from resultsDataSource: OCDataSource?, with resultsCellStyle: CollectionViewCellStyle?) {
		scopeResultsCellStyle = resultsCellStyle
		scopeResults = resultsDataSource

		resultContent = Content(type: .results, source: resultsDataSource, style: resultsCellStyle)
	}

	// Determine current content
	func refreshCurrentContent() {
		updateCurrentContent()
	}

	private var hasActiveSearchCriteria: Bool {
		var searchFieldText = searchField.text ?? ""
		if searchFieldText.count > 0 {
			let charSet = CharacterSet.whitespacesAndNewlines
			searchFieldText = searchFieldText.trimmingCharacters(in: charSet)
		}

		if searchField.tokens.count > 0 || searchFieldText.count > 0 {
			return true
		}

		if let itemScope = activeScope as? ItemSearchScope {
			return !itemScope.selectedTagIDs.isEmpty || !itemScope.selectedTagNames.isEmpty
		}

		return false
	}

	func updateCurrentContent() {
   		if !hasActiveSearchCriteria {
			currentContent = suggestionContent
		} else if scopeResultsItemCount > 0 {
			currentContent = resultContent
		} else if scopeResultsAreLoading {
			currentContent = resultContent
		} else {
			currentContent = noResultContent
		}
	}

	private var currentContent: Content? {
		didSet {
			if oldValue != currentContent {
				delegate?.search(for: self, content: currentContent)
			}
		}
	}

	// MARK: - End search
	@objc func endSearch() {
		activeScope = nil

		restoreNavigationItem()

		delegate?.search(for: self, content: nil)
		delegate?.searchEnded(for: self)
	}

	// MARK: - Restore template
	public func canRestore(savedTemplate: AnyObject) -> Bool {
		guard let scopes = scopes else {
			return false
		}

		let restoreScope: SearchScope? = scopes.first(where: { scope in
			scope.canRestore(savedTemplate: savedTemplate)
		})

		return restoreScope != nil
	}

	@discardableResult public func restore(savedTemplate: AnyObject) -> Bool {
		guard let scopes = scopes else {
			return false
		}

		let restoreScope: SearchScope? = scopes.first(where: { scope in
			scope.canRestore(savedTemplate: savedTemplate)
		})

		if let searchElements = restoreScope?.restore(savedTemplate: savedTemplate) {
			setSearchFieldContent(from: searchElements)

			if activeScope != restoreScope {
				activeScope = restoreScope
			} else {
				sendSearchFieldContentsToActiveScope()
			}

			return true
		}

		return false
	}

	public func setSearchFieldContent(from searchElements: [SearchElement]) {
		var tokens : [UISearchToken] = []
		var searchTerm : String = ""

		for searchElement in searchElements {
			if let token = searchElement as? SearchToken {
				tokens.append(token.uiSearchToken)
			} else {
				if searchTerm.count > 0 {
					searchTerm += searchTerm + " " + searchElement.text
				} else {
					searchTerm = searchElement.text
				}
			}
		}

		searchField.tokens = tokens
		searchField.text = searchTerm
		applyFilterChipStyleToSearchTokens()
	}

	// MARK: - Theme support
	private func applySearchFieldAccessoryTint(_ color: UIColor) {
		if let leftView = searchField.leftView {
			if let button = leftView as? UIButton {
				button.tintColor = color
			}
			for case let imageView as UIImageView in leftView.subviewsRecursive {
				imageView.image = imageView.image?.withRenderingMode(.alwaysTemplate)
				imageView.tintColor = color
			}
		}

		if let clearButton {
			clearButton.tintColor = color
			if var configuration = clearButton.configuration {
				configuration.baseForegroundColor = color
				clearButton.configuration = configuration
			}
		}

		scopePopup?.button.tintColor = color
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		let isDark = collection.isDark
		let iconColor = HCColor.Interaction.primarySolidNormal(isDark)

		// Keep the search field transparent so only the container provides background
		searchField.backgroundColor = .clear
		applySearchFieldAccessoryTint(iconColor)
		searchField.textColor = collection.css.getColor(.fill, selectors: [.primaryText], for: nil)

		if let placeholderString = searchField.placeholder {
			searchField.attributedPlaceholder = NSAttributedString(
				string: placeholderString,
				attributes: [.foregroundColor: HCColor.Content.gray2(isDark)]
			)
		}

		searchContainerView.backgroundColor = HCColor.Structure.appBackground(isDark)
		searchContainerView.layer.cornerRadius = Self.searchFieldContainerHeight / 2
		searchContainerView.layer.masksToBounds = true

		view.backgroundColor = collection.css.getColor(.fill, selectors: [.insetGrouped, .collection], for: nil)
		cancelToolbarButton?.tintColor = collection.css.getColor(.fill, selectors: [.navigationBar, .button], for: nil)
		applyFilterChipStyleToSearchTokens()
	}
}

extension ThemeCSSSelector {
	static let searchSuggestions = ThemeCSSSelector(rawValue: "searchSuggestions")
}
