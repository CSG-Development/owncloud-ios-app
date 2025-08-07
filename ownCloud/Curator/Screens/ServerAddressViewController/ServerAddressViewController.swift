import UIKit
import SnapKit
import ownCloudAppShared

final public class ServerAddressViewController: UIViewController {
	private let logoView = HCAppLogoView(frame: .zero)

	private lazy var serverURLTextField: HCTextFieldView = {
		let textField = HCTextFieldView(frame: .zero)
		textField.placeholder = "Server address"
		textField.textField.keyboardType = .URL
		return textField
	}()

	private lazy var nextButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .filled])
		button.setTitle("Next", for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.isEnabled = false
		return button
	}()

	private lazy var moreInfoButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle("New to Seagate Files", for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		return button
	}()

	public override func viewDidLoad() {
		super.viewDidLoad()

		view.backgroundColor = HCColor.Structure.appBackground(true)

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
	}
}
