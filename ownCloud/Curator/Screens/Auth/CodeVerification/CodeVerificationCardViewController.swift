import Combine
import UIKit
import SnapKit
import ownCloudAppShared

final public class CodeVerificationCardViewController: UIViewController, Themeable {
    private let viewModel: CodeVerificationCardViewModel

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

	init(viewModel: CodeVerificationCardViewModel) {
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
		view.translatesAutoresizingMaskIntoConstraints = false

		view.addSubview(cardView)
		cardView.snp.makeConstraints { $0.edges.equalToSuperview() }

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

		let codeView = HCCodeView(codeLength: viewModel.codeLength)
		self.codeView = codeView
		codeView.onChange = { code in
			self.viewModel.code = code
		}

		codeView.onFocus = { [weak self] in
			self?.viewModel.onCodeFocus()
			self?.scrollToCodeView()
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

		viewModel.$isValidateHidden
			.receive(on: DispatchQueue.main)
			.assign(to: \UIButton.isHidden, on: validateButton)
			.store(in: &cancellables)

		viewModel.$isResendHidden
			.receive(on: DispatchQueue.main)
			.assign(to: \UIButton.isHidden, on: resendCodeButton)
			.store(in: &cancellables)

		viewModel.$errorMessage
			.receive(on: DispatchQueue.main)
			.sink { [weak self] message in
				self?.errorLabel.isHidden = message == nil
				self?.errorLabel.text = message
			}
			.store(in: &cancellables)

		viewModel.$shouldHighlightError
			.receive(on: DispatchQueue.main)
			.sink { [weak self] shouldHighlightError in
				self?.codeView.isError = shouldHighlightError
			}
			.store(in: &cancellables)

		viewModel.$isLoaderHidden
			.receive(on: DispatchQueue.main)
			.sink { [weak self] isLoaderHidden in
				self?.spinner.isHidden = isLoaderHidden
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
		codeView.focus()
	}

	@objc private func didTapSkip() {
		viewModel.didTapSkip()
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
