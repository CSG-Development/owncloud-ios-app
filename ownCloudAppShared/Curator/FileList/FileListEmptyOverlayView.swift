import UIKit
import ownCloudSDK

/// Empty / removed folder overlay shown above the file list collection view.
final class FileListEmptyOverlayView: UIView, Themeable {
	private let iconView: UIImageView = {
		let imageView = UIImageView(image: OCSymbol.icon(forSymbolName: "folder"))
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.contentMode = .scaleAspectFit
		NSLayoutConstraint.activate([
			imageView.widthAnchor.constraint(equalToConstant: 64),
			imageView.heightAnchor.constraint(equalToConstant: 48)
		])
		return imageView
	}()

	private let titleLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .headline)
		label.textAlignment = .center
		label.numberOfLines = 0
		label.text = OCLocalizedString("No contents", nil)
		return label
	}()

	private let messageLabel: UILabel = {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false
		label.font = UIFont.preferredFont(forTextStyle: .subheadline)
		label.textAlignment = .center
		label.numberOfLines = 0
		label.text = OCLocalizedString("This folder has no contents.", nil)
		return label
	}()

	private var themeRegistered = false

	override init(frame: CGRect) {
		super.init(frame: frame)
		translatesAutoresizingMaskIntoConstraints = false
		isHidden = true

		let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, messageLabel])
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 8
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
			stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(title: String, message: String) {
		titleLabel.text = title
		messageLabel.text = message
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
		messageLabel.textColor = HCColor.Content.textSecondary(collection.isDark)
	}
}
