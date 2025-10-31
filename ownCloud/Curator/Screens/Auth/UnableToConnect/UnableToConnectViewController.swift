import UIKit
import SnapKit
import ownCloudAppShared

public final class UnableToConnectViewController: UIViewController, Themeable {
    public var onRetry: (() -> Void)?
	private lazy var backButton: UIButton = {
		let b = UIButton(type: .system)
		b.setImage(HCIcon.arrowBack, for: .normal)
		b.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
		return b
	}()

	private lazy var titleLabel: UILabel = {
		let l = UILabel()
		l.font = .systemFont(ofSize: 20, weight: .medium)
		l.text = HCL10n.Auth.UnableToConnect.navbarTitle
		return l
	}()

	private lazy var navbar: UIView = {
		let v = UIView()
		return v
	}()

	private lazy var scrollView: UIScrollView = {
		let s = UIScrollView()
		s.contentInsetAdjustmentBehavior = .never
		return s
	}()

	private lazy var contentStack: UIStackView = {
		let s = UIStackView()
		s.axis = .vertical
		s.spacing = 12
		return s
	}()

	private lazy var headerLabel: UILabel = {
		let l = UILabel()
		l.numberOfLines = 0
		return l
	}()

	private lazy var listLabel: UILabel = {
		let l = UILabel()
		l.numberOfLines = 0
		return l
	}()

	private lazy var footerLabel: UILabel = {
		let l = UILabel()
		l.numberOfLines = 0
		let tap = UITapGestureRecognizer(target: self, action: #selector(didTapSupport))
		l.addGestureRecognizer(tap)
		return l
	}()

	private lazy var retryButton: UIButton = {
		let b = ThemeRoundedButton(withSelectors: [.primary, .filled])
		b.setTitle(HCL10n.Auth.UnableToConnect.retryButtonTitle, for: .normal)
		b.snp.makeConstraints { $0.height.equalTo(40) }
		b.addTarget(self, action: #selector(didTapRetry), for: .touchUpInside)
		return b
	}()

	public override func viewDidLoad() {
		super.viewDidLoad()
		Theme.shared.register(client: self, applyImmediately: true)
		setupUI()
	}

	func numberedList(_ items: [String], font: UIFont, indent: CGFloat = 24) -> NSAttributedString {
		let result = NSMutableAttributedString()
		let paragraph = NSMutableParagraphStyle()
		paragraph.firstLineHeadIndent = 0
		paragraph.headIndent = indent
		paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])]
		paragraph.minimumLineHeight = 24
		paragraph.maximumLineHeight = 24
		let kern = font.pointSize * 0.005

		for (i, text) in items.enumerated() {
			let line = "\(i+1).\t\(text)\n"
			let attr = NSMutableAttributedString(string: line, attributes: [
				.font: font,
				.paragraphStyle: paragraph,
				.kern: kern
			])
			result.append(attr)
		}
		return result
	}

	private func setupUI() {
		view.addSubview(navbar)
		navbar.snp.makeConstraints { make in
			make.top.equalTo(view.safeAreaLayoutGuide)
			make.leading.trailing.equalToSuperview()
			make.height.equalTo(64)
		}

		navbar.addSubview(titleLabel)
		navbar.addSubview(backButton)
		backButton.snp.makeConstraints { make in
			make.leading.equalToSuperview().offset(16)
			make.centerY.equalToSuperview()
		}
		titleLabel.snp.makeConstraints { make in
			make.centerX.centerY.equalToSuperview()
		}

		view.addSubview(retryButton)
		retryButton.snp.makeConstraints { make in
			make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(24)
			make.bottom.equalTo(view.safeAreaLayoutGuide).inset(24)
		}

		view.addSubview(scrollView)
		scrollView.snp.makeConstraints { make in
			make.top.equalTo(navbar.snp.bottom)
			make.leading.trailing.equalTo(view.safeAreaLayoutGuide)
			make.bottom.equalTo(retryButton.snp.top).offset(-12)
		}

		scrollView.addSubview(contentStack)
		contentStack.snp.makeConstraints { make in
			make.top.equalToSuperview().offset(24)
			make.leading.trailing.equalToSuperview().inset(24)
			make.bottom.equalToSuperview().offset(-24)
			make.width.equalTo(scrollView.snp.width).offset(-48)
		}

		contentStack.addArrangedSubviews([
			headerLabel,
			listLabel,
			footerLabel
		])
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		view.backgroundColor = collection.css.getColor(.fill, selectors: [.auth, .background], for: nil)
		let tintColor = collection.css.getColor(.stroke, selectors: [.loginNavbar], for: nil) ?? .blue

		backButton.tintColor = tintColor

		updateLabels()
	}

	private func updateLabels() {
		let css = Theme.shared.activeCollection.css

		let textColor = css.getColor(.fill, selectors: [.text], for: nil) ?? .white

		titleLabel.textColor = textColor

		let font = UIFont.systemFont(ofSize: 16, weight: .regular)
		let kern = font.pointSize * 0.005
		let headIndent: CGFloat = 24.0

		let paragraph1 = NSMutableParagraphStyle()
		paragraph1.minimumLineHeight = 24
		paragraph1.maximumLineHeight = 24

		headerLabel.attributedText = NSAttributedString(
			string: HCL10n.Auth.UnableToConnect.headerText,
			attributes: [
				.font: font,
				.paragraphStyle: paragraph1,
				.kern: kern,
				.foregroundColor: textColor
			]
		)

		let listString = NSMutableAttributedString()
		let paragraph2 = NSMutableParagraphStyle()
		paragraph2.firstLineHeadIndent = 0
		paragraph2.headIndent = headIndent
		paragraph2.tabStops = [NSTextTab(textAlignment: .left, location: headIndent, options: [:])]
		paragraph2.minimumLineHeight = 24
		paragraph2.maximumLineHeight = 24

		let listItems = [
			HCL10n.Auth.UnableToConnect.point1,
			HCL10n.Auth.UnableToConnect.point2,
			HCL10n.Auth.UnableToConnect.point3,
			HCL10n.Auth.UnableToConnect.point4,
			HCL10n.Auth.UnableToConnect.point5
		]

		for (i, text) in listItems.enumerated() {
			let line = "\(i + 1).\t\(text)\n"
			let attr = NSMutableAttributedString(string: line, attributes: [
				.font: font,
				.paragraphStyle: paragraph2,
				.kern: kern,
				.foregroundColor: textColor
			])
			listString.append(attr)
		}
		listLabel.attributedText = listString

		let paragraph3 = NSMutableParagraphStyle()
		paragraph3.minimumLineHeight = 24
		paragraph3.maximumLineHeight = 24

		let full = NSMutableAttributedString(
			string: HCL10n.Auth.UnableToConnect.footerText,
			attributes: [
				.font: font,
				.paragraphStyle: paragraph3,
				.kern: kern,
				.foregroundColor: textColor
			]
		)

		let tintColor = css.getColor(.stroke, selectors: [.loginNavbar], for: nil) ?? .blue

		let linkRange = (full.string as NSString).range(of: HCL10n.Auth.UnableToConnect.footerLinkText)
		full.addAttributes([
			.attachment: HCConfig.supportLink,
			.foregroundColor: tintColor,
			.underlineStyle: NSUnderlineStyle.single.rawValue,
			.underlineColor: tintColor
		], range: linkRange)
		footerLabel.attributedText = full
		footerLabel.isUserInteractionEnabled = true
	}

	@objc private func didTapBack() {
		dismiss(animated: true)
	}

    @objc private func didTapRetry() {
        onRetry?()
        dismiss(animated: true)
    }

	@objc private func didTapSupport() {
		UIApplication.shared.open(HCConfig.supportLink)
	}
}
