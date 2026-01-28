import Combine
import UIKit
import SnapKit
import ownCloudAppShared

final public class DeveloperOptionsViewController: UIViewController, Themeable {
	private let viewModel: DeveloperOptionsViewModel

	private var cancellables = Set<AnyCancellable>()

	private var spinner = HCSpinnerView(frame: .zero)

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 0
		label.font = UIFont.systemFont(ofSize: 24)
		label.textAlignment = .left
		label.text = HCL10n.Auth.DevOptions.title
		return label
	}()

	private lazy var staticDeviceTextField: HCTextFieldView = {
		let textField = HCTextFieldView(frame: .zero)
		textField.title = HCL10n.Auth.DevOptions.deviceTextFieldTitle
		textField.placeholder = HCL10n.Auth.DevOptions.deviceTextFieldTitle
		textField.leftIcon = HCIcon.device
		textField.textField.keyboardType = .URL
		textField.textField.returnKeyType = .done
		textField.textField.autocorrectionType = .no
		textField.textField.autocapitalizationType = .none
		return textField
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

	private lazy var okButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle(HCL10n.Common.ok, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapOk), for: .touchUpInside)
		return button
	}()

	private lazy var cancelButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle(HCL10n.Common.cancel, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
		return button
	}()

	private lazy var settingsSwitch: UISwitch = {
		let historySwitch = UISwitch()
		historySwitch.addTarget(self, action: #selector(didToggleSettingsSwitch), for: .valueChanged)
		return historySwitch
	}()

	private lazy var settingsSwitchLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 0
		label.font = UIFont.systemFont(ofSize: 16)
		label.textAlignment = .left
		label.text = HCL10n.Auth.DevOptions.settingsSwitchLabel
		return label
	}()

	private var containerStackView: UIStackView!

	init(viewModel: DeveloperOptionsViewModel) {
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

		cardView.setContentHuggingPriority(.defaultLow, for: .horizontal)
		cardView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		cardView.snp.makeConstraints {
			$0.width.equalTo(view.safeAreaLayoutGuide).offset(-48).priority(.high)
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

		let buttonsContainer = UIStackView(arrangedSubviews: [
			HCSpacerView(nil, .horizontal), cancelButton, HCSpacerView(8, .horizontal), okButton
		])
		buttonsContainer.axis = .horizontal
		buttonsContainer.spacing = 0

		let settingsSwitchContainer = UIStackView(arrangedSubviews: [
			settingsSwitchLabel, HCSpacerView(nil, .horizontal), settingsSwitch
		])
		settingsSwitchContainer.axis = .horizontal
		settingsSwitchContainer.spacing = 0

		cardContent.addArrangedSubviews([
			titleLabel,
			HCSpacerView(24),
			staticDeviceTextField,
			HCSpacerView(8),
			settingsSwitchContainer,
			HCSpacerView(16),
			buttonsContainer
		])
	}

	private func bindViewModel() {
		staticDeviceTextField.textField.textPublisher
			.receive(on: DispatchQueue.main)
			.assign(to: \.staticDeviceAddress, on: viewModel)
			.store(in: &cancellables)

		viewModel.$staticDeviceAddress
			.removeDuplicates()
			.sink { [weak self] value in
				self?.staticDeviceTextField.textField.text = value
				self?.staticDeviceTextField.errorText = nil
			}
			.store(in: &cancellables)

		viewModel.$isLoginSettingsEnabled
			.removeDuplicates()
			.sink { [weak settingsSwitch] isOn in
				settingsSwitch?.isOn = isOn
			}
			.store(in: &cancellables)
	}

	@objc private func didTapOk() {
		if viewModel.didTapOk() {
			staticDeviceTextField.errorText = nil
			dismiss(animated: true)
		} else {
			staticDeviceTextField.errorText = HCL10n.Auth.DevOptions.deviceTextFieldInvalidURLError
		}
	}

	@objc private func didTapCancel() {
		viewModel.didTapCancel()
		dismiss(animated: true)
	}

	@objc private func didTapOverlay() {
		viewModel.didTapOverlay()
		dismiss(animated: true)
	}

	@objc private func didToggleSettingsSwitch() {
		viewModel.isLoginSettingsEnabled = settingsSwitch.isOn
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		titleLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		settingsSwitchLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
	}
}

extension DeveloperOptionsViewController: UIGestureRecognizerDelegate {
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
