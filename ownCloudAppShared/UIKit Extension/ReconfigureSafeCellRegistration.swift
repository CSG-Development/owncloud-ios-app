//
//  ReconfigureSafeCellRegistration.swift
//  ownCloudAppShared
//
//  Created by Cursor on 29.05.26.
//  Copyright © 2026 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2026, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit

/// Wraps `UICollectionView.CellRegistration` so diffable reconfigure updates return the existing cell
/// instead of dequeuing again (which UIKit asserts on).
struct ReconfigureSafeCellRegistration<Cell, Item> where Cell: UICollectionViewCell {
	private let registration: UICollectionView.CellRegistration<Cell, Item>
	private let configure: (Cell, IndexPath, Item) -> Void

	init(configure: @escaping (Cell, IndexPath, Item) -> Void) {
		self.configure = configure
		self.registration = UICollectionView.CellRegistration<Cell, Item>(handler: configure)
	}

	func dequeue(from collectionView: UICollectionView, for indexPath: IndexPath, item: Item) -> UICollectionViewCell {
		// During diffable reconfigure, UIKit requires returning the cell already visible at indexPath.
		// Dequeueing again asserts even when the visible cell has a different reuse identifier/class.
		if let existingCell = collectionView.cellForItem(at: indexPath) {
			if let cell = existingCell as? Cell {
				configure(cell, indexPath, item)
			}
			return existingCell
		}

		return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
	}
}
