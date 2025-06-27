import UIKit

public class HCNavigationLogoView: ThemeCSSView {
	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		let label = UILabel()
		label.translatesAutoresizingMaskIntoConstraints = false

		addSubview(label)

		addThemeApplier({ (_, collection, _) in
			if let titleColor = collection.css.getColor(.stroke, for: label) {
				let greenText = HCL10n.Logo.firstPart
				let defaultText = HCL10n.Logo.secondPart

				let attributedText = NSMutableAttributedString(
					string: greenText,
					attributes: [
						.font: UIFont.systemFont(ofSize: 20, weight: .regular),
						.foregroundColor: HCColor.green,
					]
				)
				attributedText.append(
					NSAttributedString(
						string: defaultText,
						attributes: [
							.font: UIFont.systemFont(ofSize: 20, weight: .regular),
							.foregroundColor: titleColor,
						]
					)
				)
				label.attributedText = attributedText
			}
		})

		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: leadingAnchor),
			label.trailingAnchor.constraint(equalTo: trailingAnchor),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		let heightConstraint = heightAnchor.constraint(equalToConstant: 44)
		heightConstraint.priority = .defaultHigh
		heightConstraint.isActive = true
	}
}
