import UIKit

open class SidebarCollectionViewListCell: ThemeableCollectionViewListCell {
	open override func updateConfiguration(using state: UICellConfigurationState) {
		super.updateConfiguration(using: state)

		if var background = self.backgroundConfiguration {
			background.cornerRadius = bounds.height / 2
			self.backgroundConfiguration = background
		}
	}
}
