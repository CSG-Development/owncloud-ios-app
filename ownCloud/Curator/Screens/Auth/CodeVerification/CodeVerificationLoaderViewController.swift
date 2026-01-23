import Combine
import UIKit
import SnapKit
import ownCloudAppShared

final public class CodeVerificationLoaderViewController: UIViewController, Themeable {
	private var spinner = HCSpinnerView(frame: .zero)

	deinit {
		Theme.shared.unregister(client: self)
	}

	init() {
		super.init(nibName: nil, bundle: nil)
	}

	public required init?(coder: NSCoder) {
		fatalError("Not implemented")
	}

	public override func viewDidLoad() {
		super.viewDidLoad()

		Theme.shared.register(client: self, applyImmediately: true)
		setupUI()
	}

	private func setupUI() {
		view.backgroundColor = .clear

		view.addSubview(spinner)
		spinner.snp.makeConstraints {
			$0.width.height.equalTo(40)
			$0.top.bottom.equalToSuperview().inset(24)
			$0.leading.trailing.equalToSuperview().inset(24)
		}
	}

	public func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) { }
}
