import UIKit
import Reusable

final class LocationTreeCell: ThemeTableViewCell, Reusable {
	private lazy var iconView: UIImageView = {
		let imageView = UIImageView()
		imageView.contentMode = .scaleAspectFit
		imageView.setContentHuggingPriority(.required, for: .horizontal)
		imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
		return imageView
	}()

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 1
		label.adjustsFontForContentSizeCategory = true
		return label
	}()

	private lazy var expandButton: UIButton = {
		let button = UIButton(type: .system)
		button.setImage(UIImage(systemName: "chevron.right"), for: .normal)
		button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
		button.addTarget(self, action: #selector(tapExpand), for: .touchUpInside)
		return button
	}()

	private lazy var activityIndicator: UIActivityIndicatorView = {
		let activityIndicator = UIActivityIndicatorView(style: .medium)
		activityIndicator.hidesWhenStopped = true
		return activityIndicator
	}()

	private var iconLeading: NSLayoutConstraint!
	private var onTapExpand: (() -> Void)?

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		setupUI()
	}
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	private func setupUI() {
		preservesSuperviewLayoutMargins = false
		contentView.preservesSuperviewLayoutMargins = false
		layoutMargins = .zero

		selectionStyle = .none

		contentView.addSubview(iconView)
		contentView.addSubview(titleLabel)
		contentView.addSubview(expandButton)
		contentView.addSubview(activityIndicator)

		iconView.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		expandButton.translatesAutoresizingMaskIntoConstraints = false
		activityIndicator.translatesAutoresizingMaskIntoConstraints = false

		iconLeading = iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)

		NSLayoutConstraint.activate([
			iconLeading,
			iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: 20),
			iconView.heightAnchor.constraint(equalToConstant: 20),

			expandButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			expandButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

			activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
			activityIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

			titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: expandButton.leadingAnchor, constant: -12),
			titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
			titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
		])

		activityIndicator.stopAnimating()
		activityIndicator.isHidden = true
	}

	override func prepareForReuse() {
		super.prepareForReuse()

		onTapExpand = nil
		activityIndicator.stopAnimating()
		expandButton.isHidden = true
		activityIndicator.isHidden = true
	}

	func configure(with item: LocationTreeItem, onTapExpand: @escaping () -> Void) {
		self.onTapExpand = onTapExpand

		// Indentation by depth
		let base: CGFloat = 12
		let perLevel: CGFloat = 16
		iconLeading.constant = base + CGFloat(item.depth) * perLevel

		iconView.image = UIImage(named: "folder", in: Bundle.sharedAppBundle, with: nil)
		titleLabel.text = item.title

		let name = item.isExpanded ? "chevron-down" : "chevron-right"
		expandButton.setImage(UIImage(named: name, in: Bundle.sharedAppBundle, with: nil), for: .normal)
		expandButton.isHidden = !item.isExpandable
		separatorInset = .zero
		layoutMargins = .zero
	}

	@objc
	private func tapExpand() {
		onTapExpand?()
	}

	override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		iconView.tintColor = collection.css.getColor(.fill, selectors: [.text], for: nil)
		expandButton.tintColor = collection.css.getColor(.fill, selectors: [.text], for: nil)

		contentView.backgroundColor = .clear
		backgroundColor = .clear
	}
}

extension ThemeCSSSelector {
	static let locationDropDown = ThemeCSSSelector(rawValue: "locationDropDown")
}
