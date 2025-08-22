import UIKit

open class SidebarCollectionViewListCell: ThemeableCollectionViewListCell {
	open override func updateConfiguration(using state: UICellConfigurationState) {
		super.updateConfiguration(using: state)
		let collection = Theme.shared.activeCollection

		if var background = backgroundConfiguration?.updated(for: state) {
			background.cornerRadius = bounds.height / 2
			self.backgroundConfiguration = background
		}

		if var content = contentConfiguration?.updated(for: state) as? UIListContentConfiguration {
			if state.isHighlighted || state.isSelected || (state.cellDropState == .targeted) {
				content.imageProperties.tintColor = collection.css.getColor(.stroke, selectors: [.highlighted], for: self)
			} else {
				content.imageProperties.tintColor = collection.css.getColor(.stroke, selectors: [], for: self)
			}
			content.image = content.image?.withRenderingMode(.alwaysTemplate)
			content.imageToTextPadding = 24
			content.imageProperties.maximumSize = CGSize(width: 24, height: 24)

			self.contentConfiguration = content
		}
	}

	open override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		setNeedsUpdateConfiguration()
	}

	open override func preferredLayoutAttributesFitting(_ attrs: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
		let attrs = super.preferredLayoutAttributesFitting(attrs)
		if attrs.size.height < 48 {
			attrs.size.height = 48
		}
		return attrs
	}
}
