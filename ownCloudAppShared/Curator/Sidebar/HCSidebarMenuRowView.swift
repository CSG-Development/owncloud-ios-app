import UIKit
import SnapKit
import ownCloudApp

final class HCSidebarMenuRowView: UIControl, Themeable {
	enum Accessory {
		case none
		case disclosure(expanded: Bool)
	}

	var icon: UIImage? {
		didSet { updateContent() }
	}

	var title: String? {
		didSet { titleLabel.text = title }
	}

	var indentLevel: Int = 0 {
		didSet { leadingConstraint?.update(offset: 16 + CGFloat(indentLevel) * 20) }
	}

	var accessory: Accessory = .none

	func setDisclosureExpanded(_ expanded: Bool, animated: Bool) {
		accessory = .disclosure(expanded: expanded)
		updateAccessory(animated: animated)
	}

	var isRowSelected: Bool = false {
		didSet { applySelectionAppearance() }
	}

	var onTap: (() -> Void)?

	private let iconView = UIImageView()
	private let titleLabel = UILabel()
	private let disclosureView = UIImageView()
	private var leadingConstraint: Constraint?

	override init(frame: CGRect) {
		super.init(frame: frame)
		configure()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		layer.cornerRadius = bounds.height / 2
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		disclosureView.tintColor = collection.css.getColor(.stroke, selectors: [.sidebar, .collection, .cell], for: self)
		applySelectionAppearance()
	}

	public override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil {
			applySelectionAppearance()
		}
	}

	private func configure() {
		cssSelectors = [.sidebar, .collection, .cell]

		backgroundColor = .clear

		iconView.contentMode = .scaleAspectFit
		iconView.isUserInteractionEnabled = false
		iconView.setContentHuggingPriority(.required, for: .horizontal)

		titleLabel.font = .systemFont(ofSize: 17)
		titleLabel.numberOfLines = 1
		titleLabel.isUserInteractionEnabled = false

		disclosureView.contentMode = .scaleAspectFit
		disclosureView.isUserInteractionEnabled = false
		disclosureView.tintColor = Theme.shared.activeCollection.css.getColor(.stroke, selectors: [.sidebar, .collection, .cell], for: nil)

		addSubview(iconView)
		addSubview(titleLabel)
		addSubview(disclosureView)

		addTarget(self, action: #selector(didTap), for: .touchUpInside)

		snp.makeConstraints {
			$0.height.greaterThanOrEqualTo(48)
		}

		iconView.snp.makeConstraints {
			leadingConstraint = $0.leading.equalToSuperview().offset(16).constraint
			$0.centerY.equalToSuperview()
			$0.width.height.equalTo(24)
		}

		titleLabel.snp.makeConstraints {
			$0.leading.equalTo(iconView.snp.trailing).offset(24)
			$0.centerY.equalToSuperview()
			$0.trailing.lessThanOrEqualTo(disclosureView.snp.leading).offset(-8)
		}

		disclosureView.snp.makeConstraints {
			$0.trailing.equalToSuperview().offset(-16)
			$0.centerY.equalToSuperview()
			$0.width.height.equalTo(16)
		}

		Theme.shared.register(client: self, applyImmediately: true)
		updateAccessory(animated: false)
	}

	private func updateContent() {
		iconView.image = icon?.withRenderingMode(.alwaysTemplate)
		applySelectionAppearance()
	}

	private func updateAccessory(animated: Bool = false) {
		switch accessory {
			case .none:
				disclosureView.isHidden = true
			case .disclosure(let expanded):
				disclosureView.isHidden = false
				let symbol = expanded ? "chevron.down" : "chevron.right"
				let updateImage = {
					self.disclosureView.image = UIImage(systemName: symbol)
				}
				if animated {
					UIView.transition(with: disclosureView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction], animations: updateImage)
				} else {
					updateImage()
				}
		}
	}

	private func applySelectionAppearance() {
		let collection = Theme.shared.activeCollection

		if isRowSelected {
			backgroundColor = collection.css.getColor(.fill, selectors: [.sidebar, .collection, .selected, .cell], for: self)
			let tint = collection.css.getColor(.stroke, selectors: [.sidebar, .collection, .selected, .cell], for: self)
			iconView.tintColor = tint
			titleLabel.textColor = tint
		} else {
			backgroundColor = .clear
			iconView.tintColor = collection.css.getColor(.stroke, selectors: [.sidebar, .collection, .cell], for: self)
			titleLabel.textColor = collection.css.getColor(.stroke, selectors: [.sidebar, .text], for: self)
		}
	}

	@objc private func didTap() {
		onTap?()
	}
}
