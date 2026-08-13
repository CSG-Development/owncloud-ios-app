import UIKit

final class FileListStatisticsFooterView: UICollectionReusableView, Themeable {
	private let label = UILabel()
	private var themeRegistered = false

	override init(frame: CGRect) {
		super.init(frame: frame)
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .footnote)
		label.textAlignment = .center
		label.numberOfLines = 0
		addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
			label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(text: String?) {
		label.text = text
		isHidden = (text == nil || text?.isEmpty == true)
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil, !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		label.textColor = HCColor.Content.textSecondary(collection.isDark)
		backgroundColor = .clear
	}
}
