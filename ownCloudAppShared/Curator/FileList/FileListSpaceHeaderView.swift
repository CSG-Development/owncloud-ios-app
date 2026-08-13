import UIKit

final class FileListSpaceHeaderView: UICollectionReusableView, Themeable {
	private let titleLabel = UILabel()
	private var themeRegistered = false

	override init(frame: CGRect) {
		super.init(frame: frame)
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
		titleLabel.numberOfLines = 1
		titleLabel.lineBreakMode = .byTruncatingTail
		addSubview(titleLabel)
		NSLayoutConstraint.activate([
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(title: String) {
		titleLabel.text = title
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil, !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		titleLabel.textColor = HCColor.Content.textPrimary(collection.isDark)
		backgroundColor = .clear
	}
}
