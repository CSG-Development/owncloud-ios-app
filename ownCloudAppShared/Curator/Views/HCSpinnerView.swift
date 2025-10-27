import UIKit

public final class HCSpinnerView: ThemeCSSView {
	private var primaryColor: UIColor = .systemBlue {
		didSet { arcA.strokeColor = primaryColor.cgColor }
	}

	private var secondaryColor: UIColor = .systemGray {
		didSet { arcB.strokeColor = secondaryColor.cgColor }
	}

	private var gapAngle: CGFloat = (.pi / 9) { didSet { setNeedsLayout(); restartAnimations() } }

	private var cycleDuration: CFTimeInterval = 1.5 { didSet { restartAnimations() } }

	private var rotationDuration: CFTimeInterval = 2.0 { didSet { restartAnimations() } }

	private var minArcFraction: CGFloat = 0.12 { didSet { restartAnimations() } }
	private var maxArcFraction: CGFloat = 0.72 { didSet { restartAnimations() } }

	// MARK: - Layers
	private let containerLayer = CALayer()
	private let arcA: CAShapeLayer = {
		let l = CAShapeLayer()
		l.fillColor = UIColor.clear.cgColor
		l.lineCap = .round
		return l
	}()
	private let arcB: CAShapeLayer = {
		let l = CAShapeLayer()
		l.fillColor = UIColor.clear.cgColor
		l.lineCap = .round
		return l
	}()

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
		cssSelector = .spinner

		arcA.strokeColor = primaryColor.cgColor
		arcB.strokeColor = secondaryColor.cgColor

		layer.addSublayer(containerLayer)
		containerLayer.addSublayer(arcA)
		containerLayer.addSublayer(arcB)
		snp.makeConstraints {
			$0.width.height.equalTo(48).priority(.high)
		}
	}

	// MARK: - Layout
	public override func layoutSubviews() {
		super.layoutSubviews()

		let lineWidth = min(bounds.size.width, bounds.size.height) / 10

		[arcA, arcB].forEach {
			$0.lineWidth = lineWidth
		}

		containerLayer.frame = bounds
		arcA.frame = bounds
		arcB.frame = bounds

		// Circle path centered in bounds
		let radius = min(bounds.width, bounds.height) / 2 - lineWidth / 2
		let center = CGPoint(x: bounds.midX, y: bounds.midY)

		let path = UIBezierPath(
			arcCenter: center,
			radius: radius,
			startAngle: -.pi / 2,              // start at top
			endAngle: (3 * .pi) / 2,           // full circle
			clockwise: true
		).cgPath

		arcA.path = path
		arcB.path = path

		// Reset stroke baseline before (re)adding animations
		applyInitialStrokeValues()
		startAnimationsIfNeeded()
	}

	// MARK: - Animation setup
	private func applyInitialStrokeValues() {
		let gap = max(0.0, min(0.25, gapAngle / (2 * .pi))) // clamp to sane fraction

		// Leading arc A: starts at 0, ends at current length (will animate)
		arcA.strokeStart = 0
		arcA.strokeEnd = minArcFraction

		// Trailing arc B: ends at (1 - gap), starts just after arc A plus gap (will animate)
		arcB.strokeEnd = 1 - gap
		arcB.strokeStart = minArcFraction + gap
	}

	private func startAnimationsIfNeeded() {
		// Prevent stacks of animations on relayout
		containerLayer.removeAnimation(forKey: "rotate")
		arcA.removeAnimation(forKey: "arcA_length")
		arcB.removeAnimation(forKey: "arcB_start")

		// Rotation
		let spin = CABasicAnimation(keyPath: "transform.rotation.z")
		spin.fromValue = 0.0
		spin.toValue = 2 * Double.pi
		spin.duration = rotationDuration
		spin.repeatCount = .greatestFiniteMagnitude
		containerLayer.add(spin, forKey: "rotate")

		// Arc length grow/shrink for A
		let easeIn = CAMediaTimingFunction(name: .easeIn)
		let easeOut = CAMediaTimingFunction(name: .easeOut)

		let aLen = CAKeyframeAnimation(keyPath: "strokeEnd")
		aLen.values = [minArcFraction, maxArcFraction, minArcFraction]
		aLen.keyTimes = [0.0, 0.5, 1.0] as [NSNumber]
		aLen.timingFunctions = [easeIn, easeOut]
		aLen.duration = cycleDuration
		aLen.repeatCount = .greatestFiniteMagnitude
		aLen.isRemovedOnCompletion = false
		arcA.add(aLen, forKey: "arcA_length")

		// Arc B start follows arc A end + gap, end stays at 1 - gap
		let gap = max(0.0, min(0.25, gapAngle / (2 * .pi)))
		let bStart = CAKeyframeAnimation(keyPath: "strokeStart")
		bStart.values = [minArcFraction + gap, maxArcFraction + gap, minArcFraction + gap]
		bStart.keyTimes = [0.0, 0.5, 1.0] as [NSNumber]
		bStart.timingFunctions = [easeIn, easeOut]
		bStart.duration = cycleDuration
		bStart.repeatCount = .greatestFiniteMagnitude
		bStart.isRemovedOnCompletion = false
		arcB.add(bStart, forKey: "arcB_start")
	}

	private func restartAnimations() {
		guard window != nil else { return }
		applyInitialStrokeValues()
		startAnimationsIfNeeded()
	}

	public override func didMoveToWindow() {
		super.didMoveToWindow()

		restartAnimations()
	}

	// MARK: - Public control
	public func start() { restartAnimations() }
	public func stop() {
		containerLayer.removeAllAnimations()
		arcA.removeAllAnimations()
		arcB.removeAllAnimations()
	}

	public override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		primaryColor = collection.css.getColor(.stroke, for: self) ?? .clear
		secondaryColor = collection.css.getColor(.fill, for: self) ?? .clear
	}
}
