import UIKit

final class HCSidebarFooterView: ThemeCSSView {
	private lazy var stackView: UIStackView = {
		let stackView = UIStackView()
		stackView.axis = .vertical
		stackView.spacing = 0
		return stackView
	}()

	private lazy var spaceLabel: UILabel = {
		let label = UILabel()
		label.font = UIFont.systemFont(ofSize: 16)
		return label
	}()

	private lazy var remainingLabel: UILabel = {
		let label = UILabel()
		label.font = UIFont.systemFont(ofSize: 16)
		return label
	}()

	private let progressView = HCProgressBarView(frame: .zero)

	public var bytesUsed: Int64? {
		didSet {
			updateView()
		}
	}

	public var bytesRemaining: Int64? {
		didSet {
			updateView()
		}
	}

	public override init(frame: CGRect) {
		super.init(frame: frame)

		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)

		commonInit()
	}

	private func commonInit() {
		layer.cornerRadius = 8
		layer.masksToBounds = true

		stackView.addArrangedSubviews([
			spaceLabel,
			HCSpacerView(8, .vertical),
			remainingLabel,
			HCSpacerView(8, .vertical),
			progressView
		])
		addSubview(stackView)
		stackView.snp.makeConstraints {
			$0.top.leading.equalToSuperview().offset(16)
			$0.bottom.trailing.equalToSuperview().offset(-16)
		}
	}

	private func updateView() {
		guard let bytesUsed else { return }

		spaceLabel.text = HCL10n.Sidebar.storageSpace

		if let bytesRemaining {
			let bytesTotal = bytesUsed + bytesRemaining
			let bytesUsedIEC = HCBytesFormatter.formatBytesIEC(bytesUsed)
			let bytesTotalIEC = HCBytesFormatter.formatBytesIEC(bytesTotal)

			remainingLabel.text = HCL10n.Sidebar.used(bytesUsedIEC, of: bytesTotalIEC)
			progressView.isHidden = false
			progressView.fraction = Float(bytesUsed) / Float(bytesTotal)
		} else {
			remainingLabel.text = HCL10n.Sidebar.unlimitedSpace
			progressView.isHidden = true
		}
	}

	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		backgroundColor = collection.css.getColor(.fill, selectors: [.sidebar, .background], for: nil)
		spaceLabel.textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		remainingLabel.textColor = collection.css.getColor(.fill, selectors: [.secondaryText], for: nil) ?? .white
	}
}
