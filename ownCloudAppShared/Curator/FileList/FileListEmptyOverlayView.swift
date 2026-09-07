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

	private let actionsStack: UIStackView = {
		let stack = UIStackView()
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .vertical
		stack.alignment = .fill
		stack.spacing = 8
		stack.isHidden = true
		return stack
	}()

	private var themeRegistered = false
	private var isDark = false
	private var actionHandlers: [() -> Void] = []

	override init(frame: CGRect) {
		super.init(frame: frame)
		translatesAutoresizingMaskIntoConstraints = false
		isHidden = true

		let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, messageLabel, actionsStack])
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 8
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
			stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
			actionsStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(title: String, message: String, actions: [(title: String, handler: () -> Void)] = []) {
		titleLabel.text = title
		messageLabel.text = message
		actionHandlers = actions.map(\.handler)

		actionsStack.arrangedSubviews.forEach {
			actionsStack.removeArrangedSubview($0)
			$0.removeFromSuperview()
		}

		for (index, action) in actions.enumerated() {
			var configuration = UIButton.Configuration.bordered()
			configuration.title = action.title
			configuration.baseForegroundColor = HCColor.Content.textPrimary(isDark)
			let button = UIButton(configuration: configuration)
			button.tag = index
			button.addTarget(self, action: #selector(actionButtonTapped(_:)), for: .primaryActionTriggered)
			actionsStack.addArrangedSubview(button)
		}

		actionsStack.isHidden = actions.isEmpty
	}

	@objc private func actionButtonTapped(_ sender: UIButton) {
		guard actionHandlers.indices.contains(sender.tag) else { return }
		actionHandlers[sender.tag]()
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil, !themeRegistered {
			themeRegistered = true
			Theme.shared.register(client: self, applyImmediately: true)
		}
	}

	func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		isDark = collection.isDark
		titleLabel.textColor = HCColor.Content.textPrimary(collection.isDark)
		messageLabel.textColor = HCColor.Content.textSecondary(collection.isDark)
		for case let button as UIButton in actionsStack.arrangedSubviews {
			var configuration = button.configuration ?? .bordered()
			configuration.baseForegroundColor = HCColor.Content.textPrimary(collection.isDark)
			button.configuration = configuration
		}
	}
}
