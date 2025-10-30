import UIKit
import SnapKit

public final class HCSpacerView: UIView {
	private let spacing: CGFloat?
	private let axis: NSLayoutConstraint.Axis

	public init(_ spacing: CGFloat? = nil, _ axis: NSLayoutConstraint.Axis = .vertical) {
		self.spacing = spacing
		self.axis = axis
		super.init(frame: .zero)

		configureViewComponents()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func configureViewComponents() {
		configureLayout()

		backgroundColor = .clear
		isUserInteractionEnabled = false
	}

	private func configureLayout() {
		guard let spacing else { return }

		switch axis {
			case .vertical:
				setContentHuggingPriority(.required, for: .vertical)
				setContentCompressionResistancePriority(.required, for: .vertical)
				snp.makeConstraints { $0.height.equalTo(spacing) }

			case .horizontal:
				setContentHuggingPriority(.required, for: .horizontal)
				setContentCompressionResistancePriority(.required, for: .horizontal)
				snp.makeConstraints { $0.width.equalTo(spacing) }

			@unknown default:
				break
		}
	}
}
