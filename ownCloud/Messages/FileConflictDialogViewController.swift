//
//  FileConflictDialogViewController.swift
//  ownCloud
//
//  Curator-styled name-conflict dialog (Replace / Keep both / Skip).
//

import UIKit
import SnapKit
import ownCloudSDK
import ownCloudAppShared

final class FileConflictDialogViewController: UIViewController, Themeable {

	struct Choice {
		let label: String
		let identifier: OCMessageChoiceIdentifier
		let type: OCIssueChoiceType
	}

	typealias ChoiceHandler = (_ choiceIdentifier: OCMessageChoiceIdentifier, _ applyToAll: Bool) -> Void

	private let titleText: String
	private let subtitleText: String
	private let choices: [Choice]
	private let showsApplyToAll: Bool
	private let onChoice: ChoiceHandler

	private lazy var cardView: HCCardView = {
		let card = HCCardView(frame: .zero)
		card.cornerRadius = Constants.cornerRadius
		card.showsShadow = false
		return card
	}()

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 0
		label.font = .systemFont(ofSize: Constants.titleFontSize, weight: .semibold)
		label.textAlignment = .center
		label.text = titleText
		return label
	}()

	private lazy var subtitleLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 0
		label.font = .systemFont(ofSize: Constants.subtitleFontSize, weight: .regular)
		label.textAlignment = .center
		label.text = subtitleText
		return label
	}()

	private lazy var applyToAllSwitch: UISwitch = {
		let control = UISwitch()
		control.accessibilityLabel = HCL10n.FileConflict.applyToAllAccessibility
		control.isOn = showsApplyToAll
		return control
	}()

	private lazy var applyToAllLabel: UILabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: Constants.subtitleFontSize, weight: .regular)
		label.text = HCL10n.FileConflict.applyToAll
		label.numberOfLines = 1
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		return label
	}()

	private lazy var applyToAllRow: UIStackView = {
		let spacer = UIView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		applyToAllLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
		applyToAllSwitch.setContentHuggingPriority(.required, for: .horizontal)
		let row = UIStackView(arrangedSubviews: [applyToAllLabel, spacer, applyToAllSwitch])
		row.axis = .horizontal
		row.alignment = .center
		row.spacing = Constants.applyToAllSpacing
		row.isHidden = !showsApplyToAll
		return row
	}()

	private lazy var buttonsStack: UIStackView = {
		let stack = UIStackView()
		stack.axis = .vertical
		stack.spacing = 0
		stack.alignment = .fill
		return stack
	}()

	private var choiceButtons: [UIButton] = []
	private var buttonSeparators: [UIView] = []

	private enum Constants {
		static let cornerRadius: CGFloat = 12
		static let titleFontSize: CGFloat = 20
		static let subtitleFontSize: CGFloat = 14
		static let contentInset: CGFloat = 24
		static let titleSubtitleSpacing: CGFloat = 8
		static let sectionSpacing: CGFloat = 16
		static let applyToAllSpacing: CGFloat = 12
		static let buttonHeight: CGFloat = 40
		static let separatorHeight: CGFloat = 1
		static let shadowBlur: CGFloat = 16
		static let shadowColor = UIColor(white: 0, alpha: 0x24 / 255.0)
	}

	init(title: String, subtitle: String, choices: [Choice], showsApplyToAll: Bool, onChoice: @escaping ChoiceHandler) {
		self.titleText = title
		self.subtitleText = subtitle
		self.choices = choices
		self.showsApplyToAll = showsApplyToAll
		self.onChoice = onChoice
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		Theme.shared.unregister(client: self)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .clear
		setupUI()
		Theme.shared.register(client: self, applyImmediately: true)
		applyDialogShadow()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		applyDialogShadow()
	}

	private func setupUI() {
		view.addSubview(cardView)
		cardView.snp.makeConstraints { $0.edges.equalToSuperview() }

		let headerStack = UIStackView(arrangedSubviews: [
			titleLabel,
			subtitleLabel,
			applyToAllRow
		])
		headerStack.axis = .vertical
		headerStack.alignment = .fill
		headerStack.spacing = Constants.sectionSpacing
		headerStack.setCustomSpacing(Constants.titleSubtitleSpacing, after: titleLabel)
		if !showsApplyToAll {
			applyToAllRow.isHidden = true
		}

		cardView.addSubview(headerStack)
		cardView.addSubview(buttonsStack)

		headerStack.snp.makeConstraints {
			$0.top.leading.trailing.equalToSuperview().inset(Constants.contentInset)
		}

		buttonsStack.snp.makeConstraints {
			$0.top.equalTo(headerStack.snp.bottom).offset(Constants.sectionSpacing)
			$0.leading.trailing.bottom.equalToSuperview()
		}

		buildChoiceButtons()
	}

	private func buildChoiceButtons() {
		buttonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
		choiceButtons.removeAll()
		buttonSeparators.removeAll()

		for (index, choice) in choices.enumerated() {
			let row = UIStackView()
			row.axis = .vertical
			row.alignment = .fill
			row.spacing = 0
			row.setContentHuggingPriority(.required, for: .vertical)

			let separator = HCSeparatorView(frame: .zero)
			separator.setContentHuggingPriority(.required, for: .vertical)
			separator.setContentCompressionResistancePriority(.required, for: .vertical)
			separator.snp.makeConstraints { $0.height.equalTo(Constants.separatorHeight) }
			buttonSeparators.append(separator)
			row.addArrangedSubview(separator)

			let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
			button.setTitle(choice.label, for: .normal)
			button.tag = index
			button.accessibilityIdentifier = choice.identifier.rawValue
			button.addTarget(self, action: #selector(didTapChoice(_:)), for: .touchUpInside)
			button.snp.makeConstraints { $0.height.equalTo(Constants.buttonHeight) }
			choiceButtons.append(button)
			row.addArrangedSubview(button)

			buttonsStack.addArrangedSubview(row)
		}
	}

	private func applyDialogShadow() {
		cardView.layer.shadowColor = Constants.shadowColor.cgColor
		cardView.layer.shadowOpacity = 1
		cardView.layer.shadowRadius = Constants.shadowBlur
		cardView.layer.shadowOffset = .zero
		cardView.layer.shadowPath = UIBezierPath(roundedRect: cardView.bounds, cornerRadius: Constants.cornerRadius).cgPath
	}

	@objc private func didTapChoice(_ sender: UIButton) {
		guard choices.indices.contains(sender.tag) else { return }
		onChoice(choices[sender.tag].identifier, showsApplyToAll && applyToAllSwitch.isOn)
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		let isDark = collection.isDark
		let textPrimary = HCColor.Content.textPrimary(isDark)
		let accent = HCColor.Structure.itemAccentHighContrast(isDark)
		let border = HCColor.Content.border2(isDark)

		titleLabel.textColor = textPrimary
		subtitleLabel.textColor = textPrimary
		applyToAllLabel.textColor = textPrimary
		applyToAllSwitch.onTintColor = accent

		for separator in buttonSeparators {
			separator.backgroundColor = border
		}
	}
}

extension FileConflictDialogViewController {
	static let keepBothCategoryIdentifiers: Set<String> = [
		"copymove.keep-both",
		"upload.keep-both"
	]

	static func isKeepBothConflict(_ message: OCMessage) -> Bool {
		guard let category = message.categoryIdentifier?.rawValue else { return false }
		return keepBothCategoryIdentifiers.contains(category)
	}

	/// Preferred display order: Replace, Keep both, Skip
	static func orderedChoices(from message: OCMessage) -> [Choice] {
		guard let choices = message.choices else { return [] }
		let preferred: [OCMessageChoiceIdentifier] = [
			OCMessageChoiceIdentifier(rawValue: "replaceExisting"),
			OCMessageChoiceIdentifier(rawValue: "keepBoth"),
			.cancel
		]
		let sorted = choices.sorted { lhs, rhs in
			let li = preferred.firstIndex(of: lhs.identifier) ?? preferred.count
			let ri = preferred.firstIndex(of: rhs.identifier) ?? preferred.count
			return li < ri
		}
		return sorted.map { choice in
			let label = (choice.identifier == .cancel) ? HCL10n.FileConflict.skip : choice.label
			return Choice(label: label, identifier: choice.identifier, type: choice.type)
		}
	}

	static func defaultChoices() -> [Choice] {
		[
			Choice(label: HCL10n.FileConflict.replace, identifier: OCMessageChoiceIdentifier(rawValue: "replaceExisting"), type: .destructive),
			Choice(label: HCL10n.FileConflict.keepBoth, identifier: OCMessageChoiceIdentifier(rawValue: "keepBoth"), type: .default),
			Choice(label: HCL10n.FileConflict.skip, identifier: .cancel, type: .cancel)
		]
	}

	static func subtitle(forFileName name: String) -> String {
		HCL10n.FileConflict.subtitle(fileName: name)
	}
}
