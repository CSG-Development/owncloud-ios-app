import UIKit

public final class HCErrorView: ThemeCSSView {
	private enum Constants {
		static let cornerRadius = 12.0
		static let titleTextSize = 16.0
		static let subtitleTextSize = 14.0
	}

	private lazy var backgroundView = {
		let view = UIView()
		view.layer.cornerRadius = Constants.cornerRadius
		view.layer.masksToBounds = true
		return view
	}()

	private lazy var titleLabel = {
		let label = UILabel()
		label.font = .boldSystemFont(ofSize: Constants.titleTextSize)
		label.numberOfLines = 0
		return label
	}()

	private lazy var subtitleLabel = {
		let label = UILabel()
		label.font = .systemFont(ofSize: Constants.subtitleTextSize)
		label.numberOfLines = 0
		return label
	}()

	private lazy var iconImageView = {
		let imageView = UIImageView()
		imageView.image = UIImage(systemName: "exclamationmark.circle.fill")
		imageView.snp.makeConstraints { $0.width.height.equalTo(24) }
		return imageView
	}()

	public var title: String? {
		didSet {
			titleLabel.text = title
			updateView()
		}
	}

	public var subtitle: String? {
		didSet {
			subtitleLabel.text = subtitle
			updateView()
		}
	}

	public override init(frame: CGRect) {
		super.init(frame: frame)

		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)

		commonInit()
	}

	private func commonInit() {
		cssSelector = .hcErrorView

		backgroundColor = .clear
		addSubview(backgroundView)

		backgroundView.snp.makeConstraints { $0.edges.equalToSuperview() }

		let vStack = UIStackView(arrangedSubviews: [
			titleLabel,
			subtitleLabel
		])
		vStack.axis = .vertical

		let containerView = UIView()
		containerView.backgroundColor = .clear
		containerView.addSubview(iconImageView)
		iconImageView.snp.makeConstraints { $0.leading.top.equalToSuperview() }

		containerView.addSubview(vStack)
		vStack.snp.makeConstraints {
			$0.top.equalToSuperview().offset(4)
			$0.leading.equalTo(iconImageView.snp.trailing).offset(20)
			$0.bottom.trailing.equalToSuperview()
		}

		addSubview(containerView)
		containerView.snp.makeConstraints {
			$0.top.leading.equalToSuperview().offset(16)
			$0.bottom.trailing.equalToSuperview().offset(-16)
		}

		updateView()
	}

	private func updateView() {
		titleLabel.isHidden = (titleLabel.text ?? "").isEmpty
		subtitleLabel.isHidden = (subtitleLabel.text ?? "").isEmpty
	}

	public override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		backgroundView.backgroundColor = collection.css.getColor(.fill, selectors: [.hcErrorView, .background], for: nil) ?? .red
		titleLabel.textColor = collection.css.getColor(.fill, selectors: [.hcErrorView, .text], for: nil) ?? .red
		subtitleLabel.textColor = collection.css.getColor(.fill, selectors: [.hcErrorView, .text], for: nil) ?? .red
		iconImageView.tintColor = collection.css.getColor(.fill, selectors: [.hcErrorView, .error], for: nil) ?? .red
	}
}
