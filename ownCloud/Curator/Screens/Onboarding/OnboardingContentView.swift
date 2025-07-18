import UIKit
import SnapKit
import ownCloudAppShared

final class OnboardingContentView: UIView {
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
		let imageView = UIImageView(image: UIImage(named: page.imageName))
		imageView.contentMode = .scaleAspectFit
		imageView.clipsToBounds = true
		imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
		return imageView
	}()

	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.text = page.title
		label.textColor = .white
		label.font = UIFont.boldSystemFont(ofSize: 22)
		label.numberOfLines = 0
		label.textAlignment = .left
		label.setContentHuggingPriority(.required, for: .vertical)
		return label
	}()

	private lazy var subtitleLabel: UILabel = {
		let label = UILabel()
		label.text = page.subtitle
		label.textColor = .white
		label.font = UIFont.systemFont(ofSize: 14)
		label.numberOfLines = 0
		label.textAlignment = .left
		label.setContentHuggingPriority(.required, for: .vertical)
		return label
	}()

	private var imageConstraint: Constraint?

	init(_ page: OnboardingPage) {
		self.page = page

		super.init(frame: .zero)

		setContentHuggingPriority(.required, for: .vertical)

		addSubview(stackView)
		stackView.snp.makeConstraints { $0.edges.equalToSuperview() }

		stackView.addArrangedSubviews([
			imageView,
			HCSpacerView(40),
			titleLabel,
			HCSpacerView(12),
			subtitleLabel
		])

		imageView.snp.makeConstraints {
			$0.height.lessThanOrEqualTo(320)
			imageConstraint = $0.height.equalTo(150).constraint
		}

		snp.makeConstraints { $0.width.lessThanOrEqualTo(312) }
		setContentHuggingPriority(.required, for: .horizontal)
		updateImageConstraint()
	}

	required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	private func updateImageConstraint() {
		imageConstraint?.isActive = useSmallerImage
		setNeedsLayout()
	}
}
