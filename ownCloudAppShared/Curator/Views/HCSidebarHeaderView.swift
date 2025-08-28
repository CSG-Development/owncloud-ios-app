import UIKit
import SnapKit
import ownCloudSDK
import ownCloudApp

public final class HCSidebarHeaderView: ThemeCSSView {
	private lazy var avatarView: UIView = {
		let view = UIView()
		view.layer.masksToBounds = true
		view.snp.makeConstraints { $0.width.height.equalTo(40) }
		return view
	}()

	private lazy var nameLabel: ThemeCSSLabel = {
		let label = ThemeCSSLabel(frame: .zero)
		label.font = UIFont.boldSystemFont(ofSize: 18)
		return label
	}()

	private lazy var emailLabel: ThemeCSSLabel = {
		let label = ThemeCSSLabel(frame: .zero)
		label.font = UIFont.systemFont(ofSize: 14)
		return label
	}()

	private lazy var editButton: UIButton = {
		let button = UIButton()
		button.setImage(UIImage(named: "pencil", in: Bundle.sharedAppBundle, with: nil), for: .normal)
		button.imageView?.contentMode = .scaleAspectFit
		button.addTarget(self, action: #selector(didTapEdit), for: .touchUpInside)
		return button
	}()

	@objc
	private func didTapEdit() {
		onEditTap?()
	}

	public var bookmark: OCBookmark? {
		didSet {
			updateView()
		}
	}

	public var onEditTap: (() -> Void)?

	public override init(frame: CGRect) {
		super.init(frame: frame)

		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)

		commonInit()
	}

	private func commonInit() {
		cssSelectors = [.hcAppLogo]

		addSubview(avatarView)

		let stackView = UIStackView()
		stackView.axis = .vertical
		stackView.spacing = 0
		stackView.alignment = .leading
		stackView.addArrangedSubviews([
			avatarView,
			HCSpacerView(12, .vertical),
			nameLabel,
			HCSpacerView(4, .vertical),
			emailLabel
		])

		addSubview(stackView)

		stackView.snp.makeConstraints {
			$0.top.equalTo(safeAreaLayoutGuide).offset(12)
			$0.leading.equalToSuperview().offset(20)
			$0.trailing.equalToSuperview().offset(-20)
			$0.bottom.equalToSuperview().offset(-24)
		}
	}

	private func updateView() {
		nameLabel.text = bookmark?.displayName
		emailLabel.text = bookmark?.shortName

		if let avatarProvider = bookmark?.avatar {
			avatarProvider.provideView(for: CGSize(width: 40, height: 40), in: nil) { view in
				guard let view else { return }
				self.avatarView.subviews.forEach { $0.removeFromSuperview() }
				self.avatarView.addSubview(view)

				if let ocCTVView = view as? OCCircularTextView {
					ocCTVView.fgColor = Theme.shared.activeCollection.css.getColor(.stroke, selectors: [.sidebar, .header, .accessory], for: nil) ?? .white
					ocCTVView.bgColor = Theme.shared.activeCollection.css.getColor(.fill, selectors: [.sidebar, .header, .accessory], for: nil) ?? .white
				}

				view.snp.makeConstraints { $0.edges.equalToSuperview() }
			}
		}
	}

	public override func layoutSubviews() {
		super.layoutSubviews()

		avatarView.layer.cornerRadius = avatarView.frame.size.height / 2.0
	}

	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		backgroundColor = collection.css.getColor(.fill, selectors: [.sidebar, .background], for: nil)

		nameLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		emailLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		editButton.tintColor = collection.css.getColor(.stroke, selectors: [.sidebar, .header, .accessory], for: nil) ?? .white

		updateView()
	}
}
