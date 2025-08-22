import UIKit

public final class HCProgressBarView: ThemeCSSView {
	var fraction: Float = 0.0 {
		didSet {
			updateView()
		}
	}

	private let progressView = UIView()

	public override init(frame: CGRect) {
		super.init(frame: frame)

		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)

		commonInit()
	}

	private func commonInit() {
		snp.makeConstraints { $0.height.equalTo(8) }
		addSubview(progressView)
		updateView()
	}

	public override func layoutSubviews() {
		super.layoutSubviews()

		layer.cornerRadius = bounds.size.height / 2.0
		progressView.layer.cornerRadius = bounds.size.height / 2.0
	}

	private func updateView() {
		progressView.snp.remakeConstraints {
			$0.left.top.bottom.equalToSuperview()
			$0.width.equalToSuperview().multipliedBy(self.fraction)
		}
	}

	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		progressView.backgroundColor = collection.css.getColor(.stroke, selectors: [.spinner], for: nil)
		backgroundColor = collection.css.getColor(.fill, selectors: [.separator], for: nil)
	}
}
