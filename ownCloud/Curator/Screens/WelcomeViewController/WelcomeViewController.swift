import UIKit
import SnapKit
import ownCloudAppShared

final public class WelcomeViewController: UIViewController {
	private lazy var backgroundImageView: UIImageView = {
		let imageView = UIImageView()
		imageView.contentMode = .scaleAspectFill
		return imageView
	}()
	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 0
		label.textAlignment = .center
		var firstPartText = AttributedString(HCL10n.Logo.firstPart)
		firstPartText.foregroundColor = HCColor.green
		var secondPartText = AttributedString(HCL10n.Logo.secondPart)
		secondPartText.foregroundColor = HCColor.white
		var attributedText = firstPartText + secondPartText
		attributedText.font = UIFont.systemFont(ofSize: 34, weight: .regular)
		label.attributedText = NSAttributedString(attributedText)
		return label
	}()
	private lazy var startSetupButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.secondary, .outlined])
		button.setTitle(HCL10n.Welcome.startSetupButtonTitle, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapStartSetup), for: .touchUpInside)
		return button
	}()
	private lazy var settingsButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .filled])
		button.setTitle(HCL10n.Welcome.settingsButtonTitle, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapSettings), for: .touchUpInside)
		return button
	}()

	public var backgroundImage: UIImage? {
		didSet {
			guard isViewLoaded else { return }
			backgroundImageView.image = backgroundImage
		}
	}

	public var onStartSetupTap: (() -> Void)?
	public var onSettingsTap: (() -> Void)?

	public override func viewDidLoad() {
		super.viewDidLoad()

		view.addSubview(backgroundImageView)
		backgroundImageView.snp.makeConstraints {
			$0.edges.equalToSuperview()
		}
		backgroundImageView.image = backgroundImage

		let stackView = UIStackView()
		stackView.spacing = 8
		stackView.axis = .vertical
		view.addSubview(stackView)
		stackView.snp.makeConstraints {
			$0.centerX.equalToSuperview()
			$0.leading.equalToSuperview().offset(24)
			$0.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-40)
		}

		stackView.addArrangedSubview(startSetupButton)
		stackView.addArrangedSubview(settingsButton)

		view.addSubview(titleLabel)
		titleLabel.snp.makeConstraints {
			$0.bottom.equalTo(stackView.snp.top).offset(-40)
			$0.centerX.equalToSuperview()
		}
	}

	@objc private func didTapStartSetup() {
		onStartSetupTap?()
	}

	@objc private func didTapSettings() {
		onSettingsTap?()
	}
}
