import UIKit
import SnapKit

public final class HCSeparatorView: ThemeCSSView {
	public override init(frame: CGRect) {
		super.init(frame: frame)

		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)

		commonInit()
	}

	private func commonInit() {
		cssSelectors = [.separator]
	}

	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		backgroundColor = collection.css.getColor(.fill, selectors: [.separator], for: nil)		
	}
}
