import UIKit
import SnapKit

extension ThemeCSSSelector {
	public static let hcAppLogo = ThemeCSSSelector(rawValue: "hcAppLogo")
	public static let part1Color = ThemeCSSSelector(rawValue: "part1Color")
	public static let part2Color = ThemeCSSSelector(rawValue: "part2Color")
}

public final class HCAppLogoView: ThemeCSSView {
	private lazy var titleLabel: UILabel = {
		let label = UILabel()
		label.numberOfLines = 0
		label.textAlignment = .center
		return label
	}()

	private var part1Color: UIColor?
	private var part2Color: UIColor?

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

		addSubview(titleLabel)
		titleLabel.snp.makeConstraints {
			$0.edges.equalToSuperview()
		}

		backgroundColor = .clear
		updateLabel()
		isUserInteractionEnabled = false
	}

	private func updateLabel() {
		var part1 = AttributedString(HCL10n.Logo.firstPart + "\n")
		part1.foregroundColor = part1Color
		part1.font = UIFont.systemFont(ofSize: 34, weight: .regular)

		var part2 = AttributedString(HCL10n.Logo.secondPart)
		part2.foregroundColor = part2Color
		part2.font = UIFont.systemFont(ofSize: 34, weight: .regular)

		titleLabel.attributedText = NSAttributedString(part1 + part2)
	}

	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		part1Color = collection.css.getColor(.stroke, selectors: [.part1Color], for: self)
		part2Color = collection.css.getColor(.stroke, selectors: [.part2Color], for: self)
		updateLabel()

		super.applyThemeCollection(theme: theme, collection: collection, event: event)
	}
}
