import UIKit

public final class HCOverlayView: ThemeCSSView {
	public override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		backgroundColor = collection.css.getColor(.fill, selectors: [.hcOverlayView, .background], for: nil) ?? .clear
	}
}
