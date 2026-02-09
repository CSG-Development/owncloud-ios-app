import UIKit
import SnapKit
import ownCloudAppShared

final class OnboardingContentView: UIView, Themeable {
	let page: OnboardingPage

	var useSmallerImage: Bool = false {
		didSet {
			updateImageConstraint()
		}
	}

	private lazy var stackView: UIStackView = {
		let stackView = UIStackView()
		stackView.axis = .vertical
		stackView.spacing = 0
		return stackView
	}()

	private lazy var imageView: UIImageView = {
		let imageView = UIImageView()
		imageView.contentMode = .scaleAspectFit
		imageView.clipsToBounds = true
		imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
		return imageView
	}()

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.text = page.title
		label.textColor = .white
		label.font = UIFont.boldSystemFont(ofSize: 34)
		label.numberOfLines = 0
		label.textAlignment = .left
		label.setContentHuggingPriority(.required, for: .vertical)
		return label
	}()

	private lazy var subtitleLabel: UILabel = {
		let label = UILabel()
		label.text = page.subtitle
		label.numberOfLines = 0
		label.textAlignment = .left
		label.setContentHuggingPriority(.required, for: .vertical)
		return label
	}()

	private lazy var installAppImageView: UIImageView = {
		let imageView = UIImageView()
		imageView.contentMode = .scaleAspectFit
		imageView.clipsToBounds = true
		imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
		return imageView
	}()

	private var imageConstraint: Constraint?

	init(_ page: OnboardingPage) {
		self.page = page

		super.init(frame: .zero)
		Theme.shared.register(client: self, applyImmediately: true)

		setContentHuggingPriority(.required, for: .vertical)

		addSubview(stackView)
		stackView.snp.makeConstraints { $0.edges.equalToSuperview() }

		stackView.addArrangedSubviews([
			imageView,
			HCSpacerView(40),
			titleLabel,
			HCSpacerView(12),
			subtitleLabel,
			HCSpacerView(24),
			HCHStack([installAppImageView, HCSpacerView(nil, .horizontal)])
		])

		imageView.snp.makeConstraints {
			$0.height.lessThanOrEqualTo(320)
			imageConstraint = $0.height.equalTo(120).constraint
		}

		snp.makeConstraints { $0.width.lessThanOrEqualTo(312) }
		setContentHuggingPriority(.required, for: .horizontal)
		updateImageConstraint()
	}

	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	deinit {
		Theme.shared.unregister(client: self)
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		if
			let installAppImageNameLight = page.installAppImageNameLight,
			let installAppImageNameDark = page.installAppImageNameDark {
			installAppImageView.image = UIImage(
				named: collection.style == .dark ? installAppImageNameDark : installAppImageNameLight
			)
		}

		imageView.image = UIImage(
			named: collection.style == .dark ? page.imageNameDark : page.imageNameLight
		)
		titleLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		subtitleLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		updateSubtitleLabel()
	}

	private func updateSubtitleLabel() {
		let font = UIFont.systemFont(ofSize: 16, weight: .regular)
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = 24
		paragraph.maximumLineHeight = 24

		let text = page.subtitle
		let kern = font.pointSize * 0.005 // 0.5% letter spacing
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.kern: kern,
			.paragraphStyle: paragraph
		]
		subtitleLabel.attributedText = NSAttributedString(string: text, attributes: attributes)
	}

	private func updateImageConstraint() {
		imageConstraint?.isActive = useSmallerImage
		setNeedsLayout()
	}
}
