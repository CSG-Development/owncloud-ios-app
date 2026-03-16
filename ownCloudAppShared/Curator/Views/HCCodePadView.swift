import UIKit

public final class HCCodePadView: ThemeCSSView {
	private enum Constants {
		static let rows: Int = 4
		static let columns: Int = 3
		static let spacingFactor: CGFloat = 0.2
	}

	private var digitButtons: [ThemeRoundedButton] = []
	private var biometryButton: UIButton?
	private var deleteButton: UIButton?

	var onDigit: ((Int) -> Void)?
	var onDelete: (() -> Void)?
	var onBiometry: (() -> Void)?

	var biometryImage: UIImage? {
		didSet {
			biometryButton?.setImage(biometryImage, for: .normal)
			biometryButton?.isHidden = (biometryImage == nil)
		}
	}

	// MARK: - Init

	public override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		cssSelector = .hcErrorView
		backgroundColor = .clear

		let factorCols = CGFloat(Constants.columns) + Constants.spacingFactor * CGFloat(Constants.columns - 1)
		let factorRows = CGFloat(Constants.rows) + Constants.spacingFactor * CGFloat(Constants.rows - 1)
		let aspectRatio = factorRows / factorCols

		snp.makeConstraints {
			$0.height.equalTo(self.snp.width).multipliedBy(aspectRatio)
		}

		setContentHuggingPriority(.defaultLow, for: .horizontal)
		setContentHuggingPriority(.defaultLow, for: .vertical)
		setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		setContentCompressionResistancePriority(.defaultLow, for: .vertical)

		recreateButtons()
	}

	private func recreateButtons() {
		digitButtons.forEach { $0.removeFromSuperview() }
		digitButtons.removeAll()
		biometryButton?.removeFromSuperview()
		deleteButton?.removeFromSuperview()

		for digit in 1...9 {
			let button = makeDigitButton(tag: digit)
			addSubview(button)
			digitButtons.append(button)
		}

		let zeroButton = makeDigitButton(tag: 0)
		addSubview(zeroButton)
		digitButtons.append(zeroButton)

		let bioBtn = UIButton(type: .system)
		bioBtn.tintColor = .white
		bioBtn.addTarget(self, action: #selector(didTapBiometry), for: .touchUpInside)
		bioBtn.isHidden = true
		addSubview(bioBtn)
		biometryButton = bioBtn

		let delBtn = UIButton(type: .system)
		delBtn.setImage(HCIcon.deleteArrow, for: .normal)
		delBtn.tintColor = .white
		delBtn.addTarget(self, action: #selector(didTapDelete), for: .touchUpInside)
		addSubview(delBtn)
		deleteButton = delBtn

		setNeedsLayout()
	}

	private func makeDigitButton(tag: Int) -> ThemeRoundedButton {
		let button = ThemeRoundedButton(withSelectors: [.primary_auth, .filled])
		button.tag = tag
		button.setTitle("\(tag)", for: .normal)
		button.addTarget(self, action: #selector(didTapDigit(sender:)), for: .touchUpInside)
		return button
	}

	@objc private func didTapDigit(sender: UIButton) {
		onDigit?(sender.tag)
	}

	@objc private func didTapBiometry() {
		onBiometry?()
	}

	@objc private func didTapDelete() {
		onDelete?()
	}

	// MARK: - Layout

	public func forceButtonRelayout() {
		for button in digitButtons {
			button.setNeedsLayout()
			button.layoutIfNeeded()
		}
	}

	public override func layoutSubviews() {
		super.layoutSubviews()
		applyLayout()
	}

	private func applyLayout() {
		let rows = Constants.rows
		let columns = Constants.columns

		guard rows > 0, columns > 0 else { return }

		let W = bounds.width
		let H = bounds.height
		guard W > 0, H > 0 else { return }

		let factorRows = CGFloat(rows) + Constants.spacingFactor * CGFloat(rows - 1)
		let factorCols = CGFloat(columns) + Constants.spacingFactor * CGFloat(columns - 1)

		let sVertical = H / factorRows
		let sHorizontal = W / factorCols
		let buttonSize = min(sVertical, sHorizontal)
		let spacing = Constants.spacingFactor * buttonSize

		let totalWidth = buttonSize * CGFloat(columns)
			+ spacing * CGFloat(columns - 1)
		let totalHeight = buttonSize * CGFloat(rows)
			+ spacing * CGFloat(rows - 1)

		let originX = (W - totalWidth) / 2.0
		let originY = (H - totalHeight) / 2.0

		let gridDigits: [[Int?]] = [
			[1, 2, 3],
			[4, 5, 6],
			[7, 8, 9],
			[nil, 0, nil]
		]

		for row in 0..<rows {
			for col in 0..<columns {
				guard row < gridDigits.count,
					  col < gridDigits[row].count,
					  let digit = gridDigits[row][col],
					  let button = digitButtons.first(where: { $0.tag == digit }) else {
					continue
				}

				let x = originX + CGFloat(col) * (buttonSize + spacing)
				let y = originY + CGFloat(row) * (buttonSize + spacing)

				button.frame = CGRect(
					x: x,
					y: y,
					width: buttonSize,
					height: buttonSize
				)
			}
		}

		// Biometry button: row 3, col 0
		let bioX = originX
		let bioY = originY + CGFloat(3) * (buttonSize + spacing)
		biometryButton?.frame = CGRect(x: bioX, y: bioY, width: buttonSize, height: buttonSize)

		// Delete button: row 3, col 2
		let delX = originX + CGFloat(2) * (buttonSize + spacing)
		let delY = bioY
		deleteButton?.frame = CGRect(x: delX, y: delY, width: buttonSize, height: buttonSize)
	}

	// MARK: - Theming

	public override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		let textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		biometryButton?.tintColor = textColor
		deleteButton?.tintColor = textColor
	}
}
