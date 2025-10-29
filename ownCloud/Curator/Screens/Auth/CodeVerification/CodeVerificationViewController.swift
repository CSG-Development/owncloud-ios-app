import Combine
import UIKit
import SnapKit
import ownCloudAppShared

final public class CodeVerificationViewController: UIViewController, Themeable {
    private let viewModel: CodeVerificationViewModel

    private var cancellables = Set<AnyCancellable>()

	private var spinner = HCSpinnerView(frame: .zero)

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 0
		label.font = UIFont.systemFont(ofSize: 24)
		label.textAlignment = .left
		label.text = HCL10n.Auth.CodeVerification.title
		return label
	}()

	private lazy var descriptionLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 0
		label.textAlignment = .left

		let font = UIFont.systemFont(ofSize: 16, weight: .regular)
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = 24
		paragraph.maximumLineHeight = 24

		let text = HCL10n.Auth.CodeVerification.description
		let kern = font.pointSize * 0.005 // 0.5% letter spacing
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.kern: kern,
			.paragraphStyle: paragraph
		]
		label.attributedText = NSAttributedString(string: text, attributes: attributes)
		return label
	}()

	private lazy var scrollView: UIScrollView = {
		let scrollView = UIScrollView()
		scrollView.contentInsetAdjustmentBehavior = .never
		return scrollView
	}()

	private lazy var overlay: HCOverlayView = {
		let overlayView = HCOverlayView()
		let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapOverlay))
		overlayView.addGestureRecognizer(tapRecognizer)
		return overlayView
	}()

	private lazy var backgroundTapRecognizer: UITapGestureRecognizer = {
		let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapOverlay))
		tapRecognizer.cancelsTouchesInView = false
		tapRecognizer.delegate = self
		return tapRecognizer
	}()

	private lazy var cardView: HCCardView = {
		HCCardView(frame: .zero)
	}()

	private lazy var hiddenCodeField: UITextField = {
		let textField = UITextField(frame: .zero)
		textField.keyboardType = .numberPad
		textField.textContentType = .oneTimeCode
		textField.autocorrectionType = .no
		textField.autocapitalizationType = .none
		textField.isHidden = true
		textField.delegate = self
		textField.addTarget(self, action: #selector(codeEditingChanged), for: .editingChanged)
		return textField
	}()

	private lazy var codeStack: UIStackView = {
		let stackView = UIStackView()
		stackView.axis = .horizontal
		stackView.alignment = .center
		stackView.distribution = .fillEqually
		stackView.spacing = 8
		return stackView
	}()

	private var digitContainers: [UIView] = []
	private var digitLabels: [UILabel] = []

	private lazy var errorLabel: UILabel = {
		let l = UILabel()
		l.font = .systemFont(ofSize: 12)
		l.textColor = .systemRed
		l.numberOfLines = 0
		l.isHidden = true

		return l
	}()

	private lazy var validateButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle(HCL10n.Auth.CodeVerification.allowAccessButtonTitle, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapValidate), for: .touchUpInside)
		return button
	}()

	private lazy var resendCodeButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle(HCL10n.Auth.CodeVerification.resendCodeButtonTitle, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapResendCode), for: .touchUpInside)
		button.isHidden = true
		return button
	}()

	private lazy var skipButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle(HCL10n.Auth.CodeVerification.skipButtonTitle, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapSkip), for: .touchUpInside)
		return button
	}()

	init(viewModel: CodeVerificationViewModel) {
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

		Theme.shared.register(client: self, applyImmediately: true)
		setupUI()
		bindViewModel()
		viewModel.startTimer()
	}

	public override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		hiddenCodeField.becomeFirstResponder()
	}

	private func setupUI() {
		view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeKeyboard)))

		view.backgroundColor = .clear

		view.addSubview(overlay)
		overlay.snp.makeConstraints { $0.edges.equalToSuperview() }

		let containerStack = UIStackView()
		containerStack.axis = .vertical
		containerStack.spacing = 0
		containerStack.isLayoutMarginsRelativeArrangement = true
		containerStack.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
		containerStack.alignment = .center
		view.addSubview(containerStack)
		containerStack.snp.makeConstraints {
			$0.top.equalTo(view.safeAreaLayoutGuide)
			$0.leading.trailing.equalToSuperview()
			$0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
		}

		view.addGestureRecognizer(backgroundTapRecognizer)

		let topSpacer = HCSpacerView(nil)
		let bottomSpacer = HCSpacerView(nil)

		containerStack.addArrangedSubviews([
			topSpacer,
			cardView,
			bottomSpacer
		])

		topSpacer.snp.makeConstraints { make in
			make.height.equalTo(bottomSpacer.snp.height)
		}

		cardView.snp.makeConstraints {
			$0.leading.greaterThanOrEqualTo(view.safeAreaLayoutGuide).offset(24)
			$0.trailing.lessThanOrEqualTo(view.safeAreaLayoutGuide).offset(-24)
			$0.width.lessThanOrEqualTo(UIDevice.current.isIpad ? 480 : 350)
		}

		cardView.addSubview(scrollView)
		scrollView.snp.makeConstraints { $0.edges.equalToSuperview() }

		let innerContentView = UIView()
		scrollView.addSubview(innerContentView)
		innerContentView.snp.makeConstraints {
			$0.edges.equalTo(scrollView.contentLayoutGuide)
			$0.width.equalTo(scrollView.frameLayoutGuide)
		}

		let cardContent = UIStackView()
		cardContent.axis = .vertical
		cardContent.spacing = 0
		innerContentView.addSubview(cardContent)
		cardContent.snp.makeConstraints {
			$0.top.bottom.equalToSuperview().inset(24)
			$0.leading.trailing.equalToSuperview().inset(24)
		}

		cardView.snp.makeConstraints { make in
			make.height.equalTo(cardContent.snp.height).offset(48).priority(.low)
		}

		let validateButtonContainer = UIView()
		validateButtonContainer.backgroundColor = .clear

		validateButtonContainer.addSubview(validateButton)
		validateButton.snp.makeConstraints { $0.edges.equalToSuperview() }

		validateButtonContainer.addSubview(resendCodeButton)
		resendCodeButton.snp.makeConstraints { $0.edges.equalToSuperview() }

		validateButtonContainer.addSubview(spinner)
		spinner.snp.makeConstraints {
			$0.center.equalToSuperview()
			$0.width.height.equalTo(24)
		}

		let buttonsContainer = UIStackView(arrangedSubviews: [
			HCSpacerView(nil, .horizontal), skipButton, HCSpacerView(8, .horizontal), validateButtonContainer
		])
		buttonsContainer.axis = .horizontal
		buttonsContainer.spacing = 0

		cardContent.addArrangedSubviews([
			titleLabel,
			HCSpacerView(24),
			descriptionLabel,
			HCSpacerView(16),
			codeStack,
			HCSpacerView(4),
			errorLabel,
			HCSpacerView(4),
			buttonsContainer,
			HCSpacerView(24)
		])

		buildDigitBoxes()
		innerContentView.addSubview(hiddenCodeField)
		hiddenCodeField.snp.makeConstraints {
			$0.height.equalTo(0)
			$0.top.equalTo(codeStack)
			$0.leading.equalTo(codeStack)
		}

		let tap = UITapGestureRecognizer(target: self, action: #selector(focusHiddenField))
		codeStack.addGestureRecognizer(tap)

	}

	@objc private func closeKeyboard() {
		_ = hiddenCodeField.resignFirstResponder()
	}

	private func bindViewModel() {
		viewModel.$isValidateEnabled
			.receive(on: DispatchQueue.main)
			.assign(to: \UIButton.isEnabled, on: validateButton)
			.store(in: &cancellables)

		viewModel.$errors
			.receive(on: DispatchQueue.main)
			.sink { [weak self] errors in
				guard let self else { return }
				self.errorLabel.isHidden = true
				self.errorLabel.text = nil
				var shouldHighlightError = false
				for e in errors {
					if case .authenticationFailed = e {
						self.errorLabel.text = HCL10n.Auth.CodeVerification.invalidCodeError
						shouldHighlightError = true
					}
					if case .serverNotFound = e {
						self.errorLabel.text = HCL10n.Auth.CodeVerification.serverError
					}
					if case .codeExpired = e {
						self.errorLabel.text = HCL10n.Auth.CodeVerification.codeExpiredError
						shouldHighlightError = true
					}
				}
				self.errorLabel.isHidden = (self.errorLabel.text?.isEmpty ?? true)
				self.updateDigitBorderColors(showError: shouldHighlightError)
			}
			.store(in: &cancellables)

			viewModel.$isLoading
				.receive(on: DispatchQueue.main)
				.sink { [weak self] isLoading in
					self?.spinner.isHidden = !isLoading
					self?.validateButton.isHidden = isLoading || (self?.viewModel.isExpired ?? false)
				}
				.store(in: &cancellables)

		viewModel.$isExpired
			.receive(on: DispatchQueue.main)
			.sink { [weak self] expired in
				self?.validateButton.isHidden = expired || (self?.viewModel.isLoading ?? false)
				self?.resendCodeButton.isHidden = !expired
				self?.updateDigitBorderColors(showError: expired)
			}
			.store(in: &cancellables)
	}

	private func updateDigitBorderColors(showError: Bool) {
		let color: CGColor = showError ? (errorLabel.textColor.cgColor) : UIColor.separator.cgColor
		for box in digitContainers {
			box.layer.borderColor = color
		}
	}

	private func buildDigitBoxes() {
		digitContainers.removeAll()
		digitLabels.removeAll()

		for _ in 0..<viewModel.codeLength {
			let box = UIView()
			box.layer.cornerRadius = 20
			box.layer.borderWidth = 1
			box.layer.borderColor = UIColor.separator.cgColor
			box.snp.makeConstraints { make in
				make.width.equalTo(40)
				make.height.equalTo(56)
			}
			let label = UILabel()
			label.font = .systemFont(ofSize: 16)
			label.textAlignment = .center
			box.addSubview(label)
			label.snp.makeConstraints { $0.center.equalToSuperview() }
			codeStack.addArrangedSubview(box)
			digitContainers.append(box)
			digitLabels.append(label)
		}
		updateDigitLabels(with: "")
	}

	private func updateDigitLabels(with text: String) {
		for (i, label) in digitLabels.enumerated() {
			if i < text.count {
				let idx = text.index(text.startIndex, offsetBy: i)
				label.text = String(text[idx])
			} else {
				label.text = ""
			}
		}
	}

	@objc private func focusHiddenField() { hiddenCodeField.becomeFirstResponder() }

	@objc private func codeEditingChanged() {
		let filtered = (hiddenCodeField.text ?? "").filter { $0.isNumber }
		let limited = String(filtered.prefix(viewModel.codeLength))
		if hiddenCodeField.text != limited { hiddenCodeField.text = limited }
		updateDigitLabels(with: limited)
		viewModel.code = limited
	}

	@objc private func didTapValidate() {
		closeKeyboard()
		viewModel.didTapValidate()
	}

	@objc private func didTapResendCode() {
		viewModel.didTapResendCode()
	}

	@objc private func didTapSkip() {
		viewModel.didTapSkip()
	}

	@objc private func didTapOverlay() {
		self.dismiss(animated: true)
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		titleLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		descriptionLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
	}
}

extension CodeVerificationViewController: UITextFieldDelegate, UIGestureRecognizerDelegate {
	public func textFieldDidBeginEditing(_ textField: UITextField) {
		viewModel.resetErrors()
		let scrollToField = { [weak self] in
			guard let self else { return }

			let targetRect = self.codeStack.superview?.convert(self.codeStack.frame, to: self.scrollView) ?? .zero
			self.scrollView.scrollRectToVisible(targetRect, animated: true)
		}

		if HCKeyboardTracker.shared.state == .dispalyed {
			scrollToField()
		} else {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				scrollToField()
			}
		}
	}

	public func textField(
		_ textField: UITextField,
		shouldChangeCharactersIn range: NSRange,
		replacementString string: String
	) -> Bool {
		let current = textField.text ?? ""
		guard let r = Range(range, in: current) else { return false }

		let newText = current.replacingCharacters(in: r, with: string)
		let filtered = newText.filter { $0.isNumber }

		return filtered.count <= viewModel.codeLength && filtered == newText
	}

	public func gestureRecognizer(
		_ gestureRecognizer: UIGestureRecognizer,
		shouldReceive touch: UITouch
	) -> Bool {
		let point = touch.location(in: view)

		if cardView.frame.contains(point) {
			return false
		}

		return true
	}
}
