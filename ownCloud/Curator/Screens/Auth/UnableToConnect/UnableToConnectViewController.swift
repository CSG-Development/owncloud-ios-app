import UIKit
import SnapKit
import ownCloudAppShared

public final class UnableToConnectViewController: UIViewController, Themeable {
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
		let font = UIFont.systemFont(ofSize: 16, weight: .regular)
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = 24
		paragraph.maximumLineHeight = 24
		let kern = font.pointSize * 0.005
		l.attributedText = NSAttributedString(
			string: HCL10n.Auth.UnableToConnect.headerText,
			attributes: [.font: font, .paragraphStyle: paragraph, .kern: kern]
		)
		return l
	}()

	private lazy var listLabel: UILabel = {
		let l = UILabel()
		l.numberOfLines = 0
		l.attributedText = numberedList(
			[
				HCL10n.Auth.UnableToConnect.point1,
				HCL10n.Auth.UnableToConnect.point2,
				HCL10n.Auth.UnableToConnect.point3,
				HCL10n.Auth.UnableToConnect.point4,
				HCL10n.Auth.UnableToConnect.point5
			],
			font: .systemFont(ofSize: 16, weight: .regular),
			indent: 24
		)
		return l
	}()

	private lazy var footerLabel: UILabel = {
		let l = UILabel()
		l.numberOfLines = 0
		let font = UIFont.systemFont(ofSize: 16, weight: .regular)
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = 24
		paragraph.maximumLineHeight = 24
		let kern = font.pointSize * 0.005
		let full = NSMutableAttributedString(
			string: HCL10n.Auth.UnableToConnect.footerText,
			attributes: [.font: font, .paragraphStyle: paragraph, .kern: kern]
		)
		let linkRange = (full.string as NSString).range(of: HCL10n.Auth.UnableToConnect.footerLinkText)
		full.addAttributes([.attachment: HCConfig.supportLink], range: linkRange)
		l.attributedText = full
		l.isUserInteractionEnabled = true
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

		view.addSubview(scrollView)
		scrollView.snp.makeConstraints { make in
			make.top.equalTo(navbar.snp.bottom)
			make.leading.trailing.bottom.equalToSuperview()
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
			footerLabel,
			HCSpacerView(12),
			retryButton
		])
	}

	public func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		view.backgroundColor = collection.css.getColor(.fill, selectors: [.auth, .background], for: nil)

		let tintColor = collection.css.getColor(
			.stroke,
			selectors: [.loginNavbar],
			for: nil
		) ?? .blue

		backButton.tintColor = tintColor

        // Style the "Support team" link to match back button color and be underlined
        if let base = footerLabel.attributedText?.mutableCopy() as? NSMutableAttributedString {
            let fullText = base.string as NSString
			let range = fullText.range(of: HCL10n.Auth.UnableToConnect.footerLinkText)
            if range.location != NSNotFound {
                base.addAttributes([
					.foregroundColor: tintColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: tintColor
                ], range: range)
                footerLabel.attributedText = base
            }
        }
	}

	@objc private func didTapBack() {
		dismiss(animated: true)
	}

	@objc private func didTapRetry() {
		dismiss(animated: true)
	}

	@objc private func didTapSupport() {
		UIApplication.shared.open(HCConfig.supportLink)
	}
}
