import UIKit

public final class HCScrollDirectionProcessor {
	public enum ScrollDirection {
		case up
		case down
		case none
	}

	private var previousOffset: CGFloat = 0
	private var accumulatedDelta: CGFloat = 0
	private var lastDirection: ScrollDirection = .none
	private let scrollThreshold: CGFloat = 100 // Minimum scroll before triggering

	var onDirectionChange: ((ScrollDirection) -> Void)?

	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		let currentOffset = scrollView.contentOffset.y
		let maxOffsetY = scrollView.contentSize.height - scrollView.bounds.height

		guard currentOffset >= 0 && currentOffset <= maxOffsetY else {
			return
		}

		let delta = currentOffset - previousOffset
		guard abs(delta) > 1 else { return }

		let newDirection: ScrollDirection = delta > 0 ? .down : .up

		if newDirection == lastDirection {
			accumulatedDelta += delta
		} else {
			accumulatedDelta = delta
			lastDirection = newDirection
		}

		if abs(accumulatedDelta) >= scrollThreshold {
			onDirectionChange?(newDirection)
			accumulatedDelta = 0
		}

		previousOffset = currentOffset
	}
}
