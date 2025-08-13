import Combine
import UIKit
import SnapKit
import ownCloudAppShared

extension ThemeCSSSelector {
	public static let loginNavbar = ThemeCSSSelector(rawValue: "loginNavbar")
}

final public class LoginViewController: UIViewController, Themeable {
	private enum Constants {
		static let navbarHeight: CGFloat = 64.0
	}

	private let viewModel: LoginViewModel

	private var cancellables = Set<AnyCancellable>()

	private let logoView = HCAppLogoView(frame: .zero)

	private lazy var loadingView: UIView = {
		let loadingLabel = ThemeCSSLabel()
		loadingLabel.cssSelector = .auth
		loadingLabel.text = "Logging in to your account"
		let loadingView = UIStackView(arrangedSubviews: [
			HCSpinnerView(frame: .zero),
			HCSpacerView(16, .vertical),
			loadingLabel
		])
		loadingView.alignment = .center
		loadingView.axis = .vertical
		loadingView.isHidden = true
		return loadingView
	}()

	private lazy var errorView: UIView = {
		let errorCardView = HCErrorView(frame: .zero)
		errorCardView.subtitle = "Incorrect email or password"
		let errorView = UIStackView(arrangedSubviews: [
			errorCardView,
			HCSpacerView(24, .vertical)
		])
		errorView.alignment = .fill
		errorView.distribution = .fill
		errorView.axis = .vertical
		errorView.isHidden = true
		return errorView
	}()

	private lazy var scrollView: UIScrollView = {
		let scrollView = UIScrollView()
		scrollView.contentInset = .init(top: Constants.navbarHeight, left: 0, bottom: 0, right: 0)
		scrollView.contentInsetAdjustmentBehavior = .never
		return scrollView
	}()

	private lazy var emailTextField: HCTextFieldView = {
		let textField = HCTextFieldView(frame: .zero)
		textField.title = "Email"
		textField.textField.keyboardType = .emailAddress
		textField.textField.returnKeyType = .next
		textField.textField.autocorrectionType = .no
		textField.textField.autocapitalizationType = .none
		textField.placeholder = "Enter email address"
		textField.textField.delegate = self
		return textField
	}()

	private lazy var addressTextField: HCTextFieldView = {
		let textField = HCTextFieldView(frame: .zero)
		textField.title = "Connecting to"
		textField.placeholder = "No device detected"
		textField.textField.keyboardType = .URL
		textField.textField.returnKeyType = .next
		textField.textField.autocorrectionType = .no
		textField.textField.autocapitalizationType = .none
		textField.textField.delegate = self
		return textField
	}()

	private lazy var passwordTextField: HCSecureTextFieldView = {
		let textField = HCSecureTextFieldView(frame: .zero)
		textField.title = "Password"
		textField.placeholder = "Enter password"
		textField.textField.returnKeyType = .done
		textField.textField.autocorrectionType = .no
		textField.textField.autocapitalizationType = .none
		textField.textField.delegate = self
		return textField
	}()

	private lazy var loginButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .filled])
		button.setTitle("Login", for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapLogin), for: .touchUpInside)
		return button
	}()

	private lazy var resetPasswordButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle("Reset Password", for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapResetPassword), for: .touchUpInside)
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

		emailTextField.textField.text = viewModel.username
		addressTextField.textField.text = viewModel.address
		passwordTextField.textField.text = viewModel.password
	}

	public required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	public override func viewDidLoad() {
		super.viewDidLoad()

		Theme.shared.register(client: self, applyImmediately: true)
		setupUI()
		bindViewModel()
	}

	private func setupUI() {
		view.addGestureRecognizer(UITapGestureRecognizer(target: self,action: #selector(closeKeyboard)))

		view.addSubview(scrollView)
		scrollView.snp.makeConstraints {
			$0.top.equalTo(view.safeAreaLayoutGuide)
			$0.leading.trailing.equalToSuperview()
			$0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
		}

		let contentView = UIView()
		scrollView.addSubview(contentView)
		contentView.snp.makeConstraints {
			$0.edges.equalToSuperview()
			$0.width.equalTo(view.snp.width)
		}

		let stackView = UIStackView()
		stackView.spacing = 0
		stackView.axis = .vertical
		contentView.addSubview(stackView)
		stackView.snp.makeConstraints {
			$0.top.bottom.equalToSuperview()
			$0.centerX.equalToSuperview()
			$0.leading.greaterThanOrEqualToSuperview().offset(24)
			$0.width.equalToSuperview().priority(.high)
			$0.width.lessThanOrEqualTo(400)
		}

		let resetPasswordButtonContainer = UIStackView(arrangedSubviews: [
			resetPasswordButton, HCSpacerView(nil, .horizontal)
		])
		resetPasswordButtonContainer.axis = .horizontal
		resetPasswordButtonContainer.spacing = 0

		let navigationBarView = UIView()

		view.addSubview(navigationBarView)
		navigationBarView.snp.makeConstraints {
			$0.top.equalTo(view.safeAreaLayoutGuide)
			$0.leading.trailing.equalToSuperview()
			$0.height.equalTo(Constants.navbarHeight)
		}
		let navbarStackView = UIStackView()
		navigationBarView.addSubview(navbarStackView)

		navbarStackView.snp.makeConstraints {
			$0.top.bottom.equalToSuperview()
			$0.leading.equalToSuperview().offset(16)
			$0.trailing.equalToSuperview().offset(-16)
		}

		navbarStackView.addArrangedSubviews([
			HCSpacerView(),
			settingsButton
		])
		

		stackView.addArrangedSubviews([
			HCSpacerView(24),
			logoView,
			HCSpacerView(24),
			emailTextField,
			HCSpacerView(12),
			addressTextField,
			HCSpacerView(12),
			passwordTextField,
			HCSpacerView(4),
			resetPasswordButtonContainer,
			HCSpacerView(24),
			errorView,

			loginButton,
			HCSpacerView(24),
			loadingView,
		])
	}

	@objc private func closeKeyboard() {
		_ = emailTextField.resignFirstResponder()
		_ = addressTextField.resignFirstResponder()
		_ = passwordTextField.resignFirstResponder()
	}

	private func bindViewModel() {
		emailTextField.textField.textPublisher
			.receive(on: DispatchQueue.main)
			.assign(to: \.username, on: viewModel)
			.store(in: &cancellables)

		addressTextField.textField.textPublisher
			.receive(on: DispatchQueue.main)
			.assign(to: \.address, on: viewModel)
			.store(in: &cancellables)

		passwordTextField.textField.textPublisher
			.receive(on: DispatchQueue.main)
			.assign(to: \.password, on: viewModel)
			.store(in: &cancellables)

		viewModel.$isLoginEnabled
			.receive(on: DispatchQueue.main)
			.assign(to: \.isEnabled, on: loginButton)
			.store(in: &cancellables)

		viewModel.$errors
			.receive(on: DispatchQueue.main)
			.sink { [weak self] errors in
				self?.emailTextField.errorText = nil
				self?.addressTextField.errorText = nil
				self?.passwordTextField.errorText = nil
				self?.errorView.isHidden = true

				for error in errors {
					switch error {
						case .authenticationFailed:
							self?.emailTextField.errorText = " "
							self?.passwordTextField.errorText = " "
							self?.errorView.isHidden = false
						case .serverNotFound:
							self?.addressTextField.errorText = "An error ocurred while connecting to the server."
					}
				}
			}
			.store(in: &cancellables)

			viewModel.$isLoading
				.receive(on: DispatchQueue.main)
				.sink { [weak self] isLoading in
					self?.loadingView.isHidden = !isLoading
					self?.loginButton.isHidden = isLoading
				}
				.store(in: &cancellables)
	}

	@objc private func didTapLogin() {
		closeKeyboard()
		viewModel.didTapLogin()
	}

	@objc private func didTapResetPassword() {
		viewModel.didTapResetPassword()
	}

	@objc private func didTapSettings() {
		viewModel.didTapSettings()
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		view.backgroundColor = collection.css.getColor(.fill, selectors: [.auth, .background], for: nil)
		settingsButton.tintColor = collection.css.getColor(.stroke, selectors: [.loginNavbar], for: nil)
	}
}

extension LoginViewController: UITextFieldDelegate {
	public func textFieldDidBeginEditing(_ textField: UITextField) {
		viewModel.resetErrors()
		let scrollToField = {
			if textField === self.emailTextField.textField {
				let targetRect = self.emailTextField.superview?.convert(self.emailTextField.frame, to: self.scrollView) ?? .zero
				self.scrollView.scrollRectToVisible(targetRect, animated: true)
				return
			}
			if textField === self.addressTextField.textField {
				let targetRect = self.addressTextField.superview?.convert(self.addressTextField.frame, to: self.scrollView) ?? .zero
				self.scrollView.scrollRectToVisible(targetRect, animated: true)
				return
			}
			if textField === self.passwordTextField.textField {
				let targetRect = self.passwordTextField.superview?.convert(self.passwordTextField.frame, to: self.scrollView) ?? .zero
				self.scrollView.scrollRectToVisible(targetRect, animated: true)
				return
			}
		}

		if HCKeyboardTracker.shared.state == .dispalyed {
			scrollToField()
		} else {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				scrollToField()
			}
		}
	}

	public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		if textField === emailTextField.textField {
			addressTextField.textField.becomeFirstResponder()
			return true
		}
		if textField === addressTextField.textField {
			passwordTextField.textField.becomeFirstResponder()
			return true
		}
		if textField === passwordTextField.textField {
			_ = passwordTextField.resignFirstResponder()
			return true
		}
		return false
	}
}
