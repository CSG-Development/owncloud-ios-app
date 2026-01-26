import Combine
import UIKit
import SnapKit
import ownCloudAppShared

final public class CodeVerificationUnknownEmailCardViewController: UIViewController, Themeable {
	private let onCancel: (() -> Void)?

	private var cancellables = Set<AnyCancellable>()

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 0
		label.font = UIFont.systemFont(ofSize: 24)
		label.textAlignment = .left
		label.text = HCL10n.Auth.CodeUnknownEmail.title
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

		let text = HCL10n.Auth.CodeUnknownEmail.description
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

	private lazy var cancelButton: UIButton = {
		let button = ThemeRoundedButton(withSelectors: [.primary, .plain])
		button.setTitle(HCL10n.Auth.CodeUnknownEmail.cancelButtonTitle, for: .normal)
		button.snp.makeConstraints { $0.height.equalTo(40) }
		button.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
		return button
	}()

	init(onCancel: (() -> Void)?) {
		self.onCancel = onCancel

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

		let buttonsContainer = UIStackView(arrangedSubviews: [
			HCSpacerView(nil, .horizontal), cancelButton
		])

		buttonsContainer.axis = .horizontal
		buttonsContainer.spacing = 0

		cardContent.addArrangedSubviews([
			titleLabel,
			HCSpacerView(24),
			descriptionLabel,
			HCSpacerView(24),
			buttonsContainer
		])
	}

	private func bindViewModel() {
	}

	@objc private func didTapCancel() {
		self.onCancel?()
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		titleLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		descriptionLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
	}
}
