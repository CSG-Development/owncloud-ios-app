import UIKit
import SnapKit
import ownCloudAppShared

final public class ServerAddressViewController: UIViewController, HCThemeable {
	private let logoView = HCAppLogoView()

	private lazy var serverURLTextField: HCTextField = {
		let textField = HCTextField()
		textField.placeholder = "Server address"
		textField.keyboardType = .URL		
		return textField
	}()

	private lazy var nextButton: UIButton = {
		let button = UIButton()
		button.setTitle(title: "Next", style: .primary(configuration: .filled), darkMode: false)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.isEnabled = false
		return button
	}()

	private lazy var moreInfoButton: UIButton = {
		let button = UIButton()
		button.setTitle(title: "New to Seagate Files", style: .primary(configuration: .plain), darkMode: false)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		return button
	}()

	public override func viewDidLoad() {
		super.viewDidLoad()

		view.backgroundColor = HCColor.Structure.appBackground

		let scrollView = UIScrollView()
		view.addSubview(scrollView)
		scrollView.snp.makeConstraints {
			$0.edges.equalToSuperview()
		}

		let contentView = UIView()
		scrollView.addSubview(contentView)
		contentView.snp.makeConstraints {
			$0.edges.equalToSuperview()
			$0.width.equalTo(scrollView.snp.width)
		}

		let stackView = UIStackView()
		stackView.spacing = 0
		stackView.axis = .vertical
		contentView.addSubview(stackView)
		stackView.snp.makeConstraints {
			$0.verticalEdges.equalToSuperview()
			$0.leading.equalToSuperview().offset(24)
			$0.trailing.equalToSuperview().offset(-24)
		}

		stackView.addArrangedSubviews([
			logoView,
			HCSpacerView(24),
			serverURLTextField,
			HCSpacerView(24),
			nextButton,
			HCSpacerView(24),
			moreInfoButton
		])

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleDataNotification(_:)),
			name: Notification.Name("HCThemeDidChange"),
			object: nil
		)
	}

	@objc private func handleDataNotification(_ notification: Notification) {
		if let info = notification.userInfo as? [String: Any],
		   let darkMode = info["darkMode"] as? Bool {
			updateTheme(darkMode: darkMode)
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self, name: Notification.Name("HCThemeDidChange"), object: nil)
	}

	public func updateTheme(darkMode: Bool) {
		serverURLTextField.updateTheme(darkMode: darkMode)
		view.backgroundColor = darkMode ? .gray : .white
	}
}
