import Combine
import UIKit
import SnapKit
import ownCloudAppShared

extension ThemeCSSSelector {
	public static let loginNavbar = ThemeCSSSelector(rawValue: "loginNavbar")
}

final public class LoginViewController: UIViewController, Themeable {
	private let viewModel: LoginViewModel

	private var cancellables = Set<AnyCancellable>()

	private let logoView = HCAppLogoView(frame: .zero)

	private lazy var usernameTextField: HCTextFieldView = {
		let textField = HCTextFieldView(frame: .zero)
		textField.placeholder = "Username"		
		return textField
	}()

	private lazy var passwordTextField: HCSecureTextFieldView = {
		let textField = HCSecureTextFieldView(frame: .zero)
		textField.placeholder = "Password"
		return textField
	}()

	private lazy var loginButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .filled])
		button.setTitle("Login", for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapLogin), for: .touchUpInside)
		return button
	}()

	private lazy var moreInfoButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle("New to Seagate Files", for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapMoreInfo), for: .touchUpInside)
		return button
	}()

	private lazy var backButton: UIButton = {
		let button = UIButton(type: .custom)
		button.setImage(UIImage(named: "arrow-back", in: Bundle.sharedAppBundle, with: nil), for: .normal)
		button.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
		return button
	}()

	private lazy var settingsButton: UIButton = {
		let button = UIButton(type: .custom)
		button.setImage(UIImage(named: "settings", in: Bundle.sharedAppBundle, with: nil), for: .normal)
		button.addTarget(self, action: #selector(didTapSettings), for: .touchUpInside)
		return button
	}()

	init(viewModel: LoginViewModel) {
		self.viewModel = viewModel
		super.init(nibName: nil, bundle: nil)
	}

	public required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	deinit {
		print("4242: LoginViewController died")
	}

	public override func viewDidLoad() {
		super.viewDidLoad()

		Theme.shared.register(client: self, applyImmediately: true)
		setupUI()
		bindViewModel()
	}

	private func setupUI() {
		let navigationBarView = UIView()

		view.addSubview(navigationBarView)
		navigationBarView.snp.makeConstraints {
			$0.top.equalTo(view.safeAreaLayoutGuide.snp.top)
			$0.leading.trailing.equalToSuperview()
			$0.height.equalTo(64)
		}
		let navbarStackView = UIStackView()
		navigationBarView.addSubview(navbarStackView)

		navbarStackView.snp.makeConstraints {
			$0.top.bottom.equalToSuperview()
			$0.leading.equalToSuperview().offset(16)
			$0.trailing.equalToSuperview().offset(-16)
		}

		navbarStackView.addArrangedSubviews([
			backButton,
			HCSpacerView(),
			settingsButton
		])

		let scrollView = UIScrollView()
		view.addSubview(scrollView)
		scrollView.snp.makeConstraints {
			$0.top.equalTo(navigationBarView.snp.bottom)
			$0.leading.trailing.bottom.equalToSuperview()
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
			HCSpacerView(12),
			passwordTextField,
			HCSpacerView(12),
			loginButton,
			HCSpacerView(24),
			moreInfoButton
		])
	}

	private func bindViewModel() {
		usernameTextField.textField.textPublisher
			.assign(to: \.username, on: viewModel)
			.store(in: &cancellables)

		passwordTextField.textField.textPublisher
			.assign(to: \.password, on: viewModel)
			.store(in: &cancellables)

		viewModel.$isLoginEnabled
			.assign(to: \.isEnabled, on: loginButton)
			.store(in: &cancellables)

//			// ViewModel.isLoading → show spinner in button
//			viewModel.$isLoading
//				.sink { [weak self] loading in
//					if loading {
//						let spinner = UIActivityIndicatorView(style: .medium)
//						spinner.startAnimating()
//						spinner.translatesAutoresizingMaskIntoConstraints = false
//						self?.loginButton.setTitle("", for: .normal)
//						self?.loginButton.addSubview(spinner)
//						NSLayoutConstraint.activate([
//							spinner.centerXAnchor.constraint(equalTo: self!.loginButton.centerXAnchor),
//							spinner.centerYAnchor.constraint(equalTo: self!.loginButton.centerYAnchor)
//						])
//					} else {
//						self?.loginButton.subviews.forEach { $0.removeFromSuperview() }
//						self?.loginButton.setTitle("Login", for: .normal)
//					}
//				}
//				.store(in: &cancellables)
//
//			// ViewModel.loginError → show/hide errorLabel
//			viewModel.$loginError
//				.sink { [weak self] error in
//					self?.errorLabel.text = error
//					self?.errorLabel.isHidden = (error == nil)
//				}
//				.store(in: &cancellables)
		}

	@objc private func didTapLogin() {
		viewModel.didTapLogin()
	}

	@objc private func didTapMoreInfo() {
		//viewModel.didTapMoreInfo()
		usernameTextField.errorText = "Test error"
	}

	@objc private func didTapBack() {

	}

	@objc private func didTapSettings() {
		viewModel.didTapSettings()
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		view.backgroundColor = collection.css.getColor(.fill, selectors: [.table], for: self.view)
		backButton.tintColor = collection.css.getColor(.stroke, selectors: [.loginNavbar], for: nil)
		settingsButton.tintColor = collection.css.getColor(.stroke, selectors: [.loginNavbar], for: nil)
	}
}
