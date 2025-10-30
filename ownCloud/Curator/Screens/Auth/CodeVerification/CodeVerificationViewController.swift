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
		return overlayView
	}()

	private lazy var cardView: HCCardView = {
		HCCardView(frame: .zero)
	}()

	private lazy var errorLabel: UILabel = {
		let l = UILabel()
		l.font = .systemFont(ofSize: 12)
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

	private var codeView: HCCodeView!

	private var containerStackView: UIStackView!

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
	}

	public override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		codeView.focus()
	}

	private func setupUI() {
		view.backgroundColor = .clear

		view.addSubview(overlay)
		overlay.snp.makeConstraints { $0.edges.equalToSuperview() }

		let containerStackView = UIStackView()
		containerStackView.axis = .vertical
		containerStackView.spacing = 0
		containerStackView.isLayoutMarginsRelativeArrangement = true
		containerStackView.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
		containerStackView.alignment = .center
		view.addSubview(containerStackView)
		self.containerStackView = containerStackView
		let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapOverlay))
		tapRecognizer.delegate = self
		containerStackView.addGestureRecognizer(tapRecognizer)
		containerStackView.snp.makeConstraints {
			$0.top.equalTo(view.safeAreaLayoutGuide)
			$0.leading.trailing.equalToSuperview()
			$0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
		}

		let topSpacer = HCSpacerView(nil, .vertical)
		let bottomSpacer = HCSpacerView(nil, .vertical)

		containerStackView.addArrangedSubviews([
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

		let errorLabelContainer = UIStackView(arrangedSubviews: [
			HCSpacerView(16, .horizontal), errorLabel, HCSpacerView(nil, .horizontal)
		])
		buttonsContainer.axis = .horizontal
		buttonsContainer.spacing = 0

		let codeView = HCCodeView(codeLength: viewModel.codeLength)
		self.codeView = codeView
		codeView.onChange = { code in
			self.viewModel.code = code
		}
		codeView.onFocus = {
			self.viewModel.resetErrors()
			self.scrollToCodeView()
		}

		cardContent.addArrangedSubviews([
			titleLabel,
			HCSpacerView(24),
			descriptionLabel,
			HCSpacerView(16),
			codeView,
			HCSpacerView(4),
			errorLabelContainer,
			HCSpacerView(24),
			buttonsContainer
		])
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
				let isCodeExpired = errors.contains(where: {
					$0 == .codeExpired
				})
				self.errorLabel.isHidden = (self.errorLabel.text?.isEmpty ?? true)
				self.codeView.isError = shouldHighlightError

				self.resendCodeButton.isHidden = !isCodeExpired
				self.validateButton.isHidden = isCodeExpired
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
			}
			.store(in: &cancellables)
	}

	@objc private func didTapValidate() {
		codeView.unfocus()
		viewModel.didTapValidate()
	}

	@objc private func didTapResendCode() {
		viewModel.didTapResendCode()
		codeView.clearCode()
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
		errorLabel.textColor = collection.css.getColor(.stroke, selectors: [.hcDigitBox, .error], for: nil) ?? .white
	}

	private func scrollToCodeView() {
		let scrollToField = { [weak self] in
			guard let self else { return }

			let targetRect = self.codeView.superview?.convert(self.codeView.frame, to: self.scrollView) ?? .zero
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
}

extension CodeVerificationViewController: UITextFieldDelegate, UIGestureRecognizerDelegate {
	public func gestureRecognizer(
		_ gestureRecognizer: UIGestureRecognizer,
		shouldReceive touch: UITouch
	) -> Bool {
		let point = touch.location(in: containerStackView)

		if cardView.frame.contains(point) {
			return false
		}

		return true
	}
}
