import Combine
import SnapKit
import UIKit
import ownCloudAppShared

extension ThemeCSSSelector {
	public static let loginNavbar = ThemeCSSSelector(rawValue: "loginNavbar")
}

final public class LoginViewController: UIViewController, Themeable {
	private enum Constants {
		static let navbarHeight: CGFloat = 64.0
	}

	let viewModel: LoginViewModel

	private var cancellables = Set<AnyCancellable>()

	private lazy var logoView: HCAppLogoView = {
		let logoView = HCAppLogoView(frame: .zero)

		let recognizer = UITapGestureRecognizer(target: self, action: #selector(fillTestInfo))
		recognizer.numberOfTapsRequired = 5
		logoView.addGestureRecognizer(recognizer)

		return logoView
	}()

	private var loadingView: UIView!

	private lazy var errorStackView: UIStackView = {
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

	private lazy var errorCardView = HCErrorView(frame: .zero)

	private lazy var scrollView: UIScrollView = {
		let scrollView = UIScrollView()
		scrollView.contentInset = .zero
		scrollView.contentInsetAdjustmentBehavior = .never
		return scrollView
	}()

	private lazy var emailTextField: HCTextFieldView = {
		let textField = HCTextFieldView(frame: .zero)
		textField.title = HCL10n.Auth.Login.EmailField.title
		textField.placeholder = HCL10n.Auth.Login.EmailField.placeholder
		textField.textField.keyboardType = .emailAddress
		textField.textField.returnKeyType = .next
		textField.textField.autocorrectionType = .no
		textField.textField.autocapitalizationType = .none
		textField.textField.textContentType = .username
		textField.textField.delegate = self
		return textField
	}()

	private lazy var emailLabel: UILabel = {
		let label = UILabel()
		label.font = UIFont.systemFont(ofSize: 16)
		return label
	}()

	private lazy var emailLabelContainer: UIView = {
		let view = UIView()
		view.backgroundColor = .clear
		return view
	}()

	private lazy var passwordTextField: HCSecureTextFieldView = {
		let textField = HCSecureTextFieldView(frame: .zero)
		textField.title = HCL10n.Auth.Login.PasswordField.title
		textField.placeholder = HCL10n.Auth.Login.PasswordField.placeholder
		textField.textField.returnKeyType = .done
		textField.textField.autocorrectionType = .no
		textField.textField.autocapitalizationType = .none
		textField.textField.textContentType = .password
		textField.textField.delegate = self
		return textField
	}()

	private lazy var logoImageContainer: UIView = {
		let view = UIView()
		view.backgroundColor = .clear

		let imageView = UIImageView()
		imageView.contentMode = .scaleAspectFit
		view.addSubview(imageView)
		imageView.image = HCIcon.logo

		imageView.snp.makeConstraints {
			$0.width.height.equalTo(140)
			$0.center.equalToSuperview()
		}
		view.snp.makeConstraints { $0.height.equalTo(140) }
		return view
	}()

	private lazy var loginButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .filled])
		button.setTitle(HCL10n.Auth.Login.loginButtonTitle, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapLogin), for: .touchUpInside)
		return button
	}()

	private lazy var resetPasswordButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle(HCL10n.Auth.Login.resetPasswordButtonTitle, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapResetPassword), for: .touchUpInside)
		return button
	}()

	private lazy var oldLoginButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle(HCL10n.Auth.Login.oldLoginButtonTitle, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapOldLogin), for: .touchUpInside)
		return button
	}()

	private var addressDropdown: HCDropdownTextFieldView!
	private var settingsButton: UIButton!
	private var backButton: UIButton!
	private var stackView: UIStackView!
	private var refreshButton: UIButton!
	private var smallSpinner: HCSpinnerView!
	private var addressRowView: UIStackView!
	private var resetPasswordButtonContainerRef: UIStackView!
	private var oldLoginButtonContainerRef: UIStackView!

	init(viewModel: LoginViewModel) {
		self.viewModel = viewModel

		super.init(nibName: nil, bundle: nil)
	}

	deinit {
		Theme.shared.unregister(client: self)
	}

	public required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	public override func viewDidLoad() {
		super.viewDidLoad()

		let settingsButton = UIButton(type: .custom)
		settingsButton.setImage(HCIcon.settings, for: .normal)
		settingsButton.addTarget(self, action: #selector(didTapSettings), for: .touchUpInside)
		self.settingsButton = settingsButton

		let backButton = UIButton(type: .system)
		backButton.setImage(HCIcon.arrowBack, for: .normal)
		backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
		backButton.isHidden = true
		self.backButton = backButton

		let loadingLabel = ThemeCSSLabel()
		loadingLabel.cssSelector = .auth
		loadingLabel.text = HCL10n.Auth.Login.loadingViewTitle
		let loadingView = UIStackView(arrangedSubviews: [
			HCSpinnerView(frame: .zero),
			HCSpacerView(16, .vertical),
			loadingLabel
		])
		loadingView.alignment = .center
		loadingView.axis = .vertical
		self.loadingView = loadingView

		let dropdown = HCDropdownTextFieldView(frame: .zero)
		dropdown.dropdownHostView = self.view
		dropdown.title = HCL10n.Auth.Login.DeviceDropdownField.title
		dropdown.placeholder = HCL10n.Auth.Login.DeviceDropdownField.placeholder
		dropdown.onSelection = { [weak self] index, value in
			self?.viewModel.selectedDeviceIndex = index
		}
		dropdown.onFooterTap = { [weak self] in
			guard let self else { return }
			let vc = UnableToConnectViewController()
			vc.onRetry = { [weak self] in
				self?.viewModel.refreshDevices()
			}
			self.present(vc, animated: true)
		}
		self.addressDropdown = dropdown

		setupUI()
		bindViewModel()
		emailLabelContainer.addSubview(emailLabel)
		emailLabel.snp.makeConstraints {
			$0.top.bottom.centerX.equalToSuperview()
			$0.leading.greaterThanOrEqualToSuperview()
		}

		emailTextField.textField.text = viewModel.username
		passwordTextField.textField.text = viewModel.password

		Theme.shared.register(client: self, applyImmediately: true)
	}

	public override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		update(for: viewModel.step)
	}

	private func setupUI() {
		view.addGestureRecognizer(
			UITapGestureRecognizer(target: self, action: #selector(closeKeyboard))
		)

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

		// Ensure content view is at least as tall as the visible scroll area so content can center vertically
		contentView.snp.makeConstraints { $0.height.greaterThanOrEqualTo(scrollView.snp.height) }

		// A container used for centering content; includes the transparent navbar area
		let contentContainer = UIView()
		contentView.addSubview(contentContainer)
		contentContainer.snp.makeConstraints {
			$0.edges.equalToSuperview()
		}

		let stackView = UIStackView()
		stackView.spacing = 0
		stackView.axis = .vertical
		contentContainer.addSubview(stackView)
		self.stackView = stackView
		stackView.snp.makeConstraints {
			$0.top.greaterThanOrEqualToSuperview()
			$0.bottom.lessThanOrEqualToSuperview()
			$0.centerY.equalToSuperview().offset(-24).priority(.low)
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
		self.resetPasswordButtonContainerRef = resetPasswordButtonContainer

		let oldLoginButtonContainer = UIStackView(arrangedSubviews: [
			oldLoginButton, HCSpacerView(nil, .horizontal)
		])
		oldLoginButtonContainer.axis = .horizontal
		oldLoginButtonContainer.spacing = 0
		self.oldLoginButtonContainerRef = oldLoginButtonContainer

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
			backButton,
			HCSpacerView(),
			settingsButton
		])

		let addressRow = UIStackView()
		addressRow.axis = .horizontal
		addressRow.spacing = 8
		addressRow.alignment = .fill
		addressRow.distribution = .fill
		addressDropdown.setContentHuggingPriority(.defaultLow, for: .horizontal)
		addressDropdown.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		addressRow.addArrangedSubview(addressDropdown)
		let refreshContainer = UIView()
		refreshContainer.snp.makeConstraints {
			$0.width.equalTo(24)
		}
		refreshContainer.setContentHuggingPriority(.required, for: .horizontal)
		refreshContainer.setContentCompressionResistancePriority(.required, for: .horizontal)

		let refreshButton = UIButton(type: .system)
		refreshButton.setImage(HCIcon.reset, for: .normal)
		refreshContainer.addSubview(refreshButton)
		refreshButton.snp.makeConstraints {
			$0.width.height.equalTo(24)
			$0.centerX.equalToSuperview()
			$0.top.equalTo(16)
		}

		let smallSpinner = HCSpinnerView(frame: .zero)
		smallSpinner.isHidden = true

		refreshContainer.addSubview(smallSpinner)

		smallSpinner.snp.makeConstraints { $0.edges.equalTo(refreshButton) }

		addressRow.addArrangedSubview(refreshContainer)
		refreshButton.addTarget(self, action: #selector(didTapRefreshDevices), for: .touchUpInside)

		self.refreshButton = refreshButton
		self.smallSpinner = smallSpinner
		self.addressRowView = addressRow

		stackView.addArrangedSubviews(arrangedSubviews(for: viewModel.step, isLoading: viewModel.isLoading))

		update(for: viewModel.step)
	}

	private func arrangedSubviews(for step: LoginViewModel.Step, isLoading: Bool) -> [UIView] {
		if isLoading {
			return [
				logoImageContainer,
				logoView,
				HCSpacerView(24),
				loadingView
			]
		}
		switch step {
			case .emailEntry:
				return [
					logoImageContainer,
					logoView,
					HCSpacerView(24),
					emailTextField,
					HCSpacerView(24),
					loginButton,
					HCSpacerView(24),
					oldLoginButtonContainerRef
				]
			case .deviceSelection:
				return [
					logoImageContainer,
					logoView,
					HCSpacerView(24),
					emailLabelContainer,
					HCSpacerView(32),
					addressRowView,
					HCSpacerView(12),
					passwordTextField,
					HCSpacerView(4),
					(resetPasswordButtonContainerRef ?? UIStackView(arrangedSubviews: [resetPasswordButton, HCSpacerView(nil, .horizontal)])),
					HCSpacerView(24),
					loginButton,
					HCSpacerView(24),
					errorStackView
				]
		}
	}

	private func update(for step: LoginViewModel.Step) {
		guard let stackView else { return }
		stackView.arrangedSubviews.forEach { stackView.removeArrangedSubview($0); $0.removeFromSuperview() }
		stackView.addArrangedSubviews(arrangedSubviews(for: step, isLoading: viewModel.isLoading))

		switch step {
			case .emailEntry:
				emailTextField.textField.isEnabled = true
				loginButton.setTitle(HCL10n.Auth.Login.nextButtonTitle, for: .normal)
				backButton.isHidden = true
			case .deviceSelection:
				emailTextField.textField.isEnabled = false
				emailLabel.text = viewModel.username
				loginButton.setTitle(HCL10n.Auth.Login.loginButtonTitle, for: .normal)
				backButton.isHidden = false
		}
		view.layoutIfNeeded()
	}

	@objc private func fillTestInfo() {
		viewModel.fillTestInfo()
	}

	@objc private func closeKeyboard() {
		_ = emailTextField.resignFirstResponder()
		_ = passwordTextField.resignFirstResponder()
	}

	private func bindViewModel() {
		emailTextField.textField.textPublisher
			.receive(on: DispatchQueue.main)
			.assign(to: \.username, on: viewModel)
			.store(in: &cancellables)

		viewModel.$username
			.removeDuplicates()
			.sink { [weak emailTextField] in emailTextField?.textField.text = $0 }
			.store(in: &cancellables)

		viewModel.$deviceItems
			.receive(on: DispatchQueue.main)
			.sink { [weak addressDropdown] items in
				addressDropdown?.items = items

				addressDropdown?.leftIcon = items.isEmpty ? nil : HCIcon.device
			}
			.store(in: &cancellables)

		viewModel.$isDetectingDevices
			.receive(on: DispatchQueue.main)
			.sink { [weak self] detecting in
				guard let self else { return }

				let dropdown = self.addressDropdown
				dropdown?.placeholder = detecting ? HCL10n.Auth.Login.detectingDevices : HCL10n.Auth.Login.noDeviceDetected
				if detecting {
					dropdown?.textField.text = ""
					dropdown?.selectedIndex = nil
					self.refreshButton.isHidden = true
					self.smallSpinner.isHidden = false
					self.smallSpinner.start()
				} else {
					self.smallSpinner.stop()
					self.smallSpinner.isHidden = true
					self.refreshButton.isHidden = false
				}
			}
			.store(in: &cancellables)

		viewModel.$selectedDeviceIndex
			.receive(on: DispatchQueue.main)
			.sink { [weak addressDropdown] idx in
				addressDropdown?.selectedIndex = idx
			}
			.store(in: &cancellables)

		passwordTextField.textField.textPublisher
			.receive(on: DispatchQueue.main)
			.assign(to: \.password, on: viewModel)
			.store(in: &cancellables)

		viewModel.$password
			.removeDuplicates()
			.sink { [weak passwordTextField] in passwordTextField?.textField.text = $0 }
			.store(in: &cancellables)

		viewModel.$isLoginEnabled
			.receive(on: DispatchQueue.main)
			.assign(to: \.isEnabled, on: loginButton)
			.store(in: &cancellables)

		viewModel.$step
			.receive(on: DispatchQueue.main)
			.sink { [weak self] step in self?.update(for: step) }
			.store(in: &cancellables)

		viewModel.$isLoading
			.removeDuplicates()
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				guard let self else { return }

				self.update(for: self.viewModel.step)
			}
			.store(in: &cancellables)

		viewModel.$errors
			.receive(on: DispatchQueue.main)
			.sink { [weak self] errors in
				guard let self else { return }

				self.emailTextField.errorText = nil
				self.passwordTextField.errorText = nil
				self.errorStackView.isHidden = true

				for e in errors {
					switch e {
						case .authenticationFailed:
							self.emailTextField.errorText = " "
							self.passwordTextField.errorText = " "
							self.errorStackView.isHidden = false
							self.errorCardView.subtitle = HCL10n.Auth.Login.incorrectEmailPassword
						case .serverNotFound:
							self.errorStackView.isHidden = false
							self.errorCardView.subtitle = HCL10n.Auth.Login.connectionError
					}
				}
			}
			.store(in: &cancellables)
	}

	@objc private func didTapRefreshDevices() {
		viewModel.refreshDevices()
	}

	@objc private func didTapLogin() {
		closeKeyboard()
		viewModel.didTapLogin()
	}

	@objc private func didTapResetPassword() {
		viewModel.didTapResetPassword()
	}

	@objc private func didTapOldLogin() {
		viewModel.didTapOldLogin()
	}

	@objc private func didTapSettings() {
		viewModel.didTapSettings()
	}

	@objc private func didTapBack() {
		viewModel.backToEmailEntry()
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		emailLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil)
		view.backgroundColor = collection.css.getColor(.fill, selectors: [.auth, .background], for: nil)
		settingsButton.tintColor = collection.css.getColor(.stroke, selectors: [.loginNavbar], for: nil)
		refreshButton.tintColor = collection.css.getColor(.stroke, selectors: [.loginNavbar], for: nil)
		backButton.tintColor = collection.css.getColor(.stroke, selectors: [.loginNavbar], for: nil)
	}
}

extension LoginViewController: UITextFieldDelegate {
	public func textFieldDidBeginEditing(_ textField: UITextField) {
		viewModel.resetErrors()
		let scrollToField = {
			if textField === self.emailTextField.textField {
				let targetRect =
					self.emailTextField.superview?.convert(
						self.emailTextField.frame,
						to: self.scrollView
					) ?? .zero
				self.scrollView.scrollRectToVisible(targetRect, animated: true)
				return
			}
			if textField === self.passwordTextField.textField {
				let targetRect =
					self.passwordTextField.superview?.convert(
						self.passwordTextField.frame,
						to: self.scrollView
					) ?? .zero
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
			passwordTextField.textField.becomeFirstResponder()
			return true
		}
		if textField === passwordTextField.textField {
			_ = passwordTextField.resignFirstResponder()
			return true
		}
		return false
	}

	public func textFieldDidEndEditing(_ textField: UITextField) {
		guard textField === emailTextField.textField else { return }

		// Only validate during email entry step
		if viewModel.step == .emailEntry {
			let text = textField.text ?? ""
			let isValid = Self.validateEmail(text)
			emailTextField.errorText = isValid ? nil : HCL10n.Auth.Login.invalidEmail
		}
	}

	private static func validateEmail(_ email: String) -> Bool {
		// Simple RFC 5322-like regex
		let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
		return email.range(of: pattern, options: .regularExpression) != nil
	}
}
