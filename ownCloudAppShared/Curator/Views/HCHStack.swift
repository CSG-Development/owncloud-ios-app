import UIKit
import SnapKit

public final class HCHStack: UIView {
	public private(set) var stackView: UIStackView!

	public init(_ subviews: [UIView]) {
		super.init(frame: .zero)

		backgroundColor = .clear

		stackView = UIStackView()
		stackView.axis = .horizontal
		stackView.spacing = 0
		stackView.distribution = .fill

		addSubview(stackView)
		stackView.snp.makeConstraints { $0.edges.equalToSuperview() }
		stackView.addArrangedSubviews(subviews)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}

