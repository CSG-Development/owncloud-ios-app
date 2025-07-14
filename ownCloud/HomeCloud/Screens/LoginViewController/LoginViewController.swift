import UIKit
import SnapKit
import ownCloudAppShared

final public class LoginViewController: UIViewController, HCThemeable {
	private let logoView = HCAppLogoView()

	private lazy var usernameTextField: HCTextField = {
		let textField = HCTextField()
		textField.placeholder = "Username"
		return textField
	}()

	private lazy var passwordTextField: HCTextField = {
		let textField = HCSecureTextField()
		textField.placeholder = "Password"
		return textField
	}()

	private lazy var loginButton: UIButton = {
		let button = UIButton()
		button.setTitle(title: "Login", style: .primary(configuration: .filled), darkMode: false)
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
			usernameTextField,
			HCSpacerView(24),
			passwordTextField,
			HCSpacerView(24),
			loginButton,
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
		usernameTextField.updateTheme(darkMode: darkMode)
		passwordTextField.updateTheme(darkMode: darkMode)
		view.backgroundColor = darkMode ? .gray : .white
	}
}
