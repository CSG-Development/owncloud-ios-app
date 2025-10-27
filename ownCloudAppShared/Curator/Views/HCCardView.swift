import UIKit

public final class HCCardView: ThemeCSSView {
	private enum Constants {
		static let cornerRadius = 28.0
	}

	public override init(frame: CGRect) {
		super.init(frame: frame)

		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)

		commonInit()
	}

    private let contentViewInternal = UIView()

    public var showsShadow: Bool = false {
        didSet { updateShadow() }
    }

    private func commonInit() {
		cssSelector = .hcCardView

        layer.cornerRadius = Constants.cornerRadius
        layer.masksToBounds = false // keep shadow visible

        // Add a content container that clips to rounded corners
        contentViewInternal.isUserInteractionEnabled = true
        contentViewInternal.layer.cornerRadius = Constants.cornerRadius
        contentViewInternal.layer.zPosition = 0
        contentViewInternal.layer.masksToBounds = true
        super.addSubview(contentViewInternal)
        contentViewInternal.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentViewInternal.topAnchor.constraint(equalTo: topAnchor),
            contentViewInternal.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentViewInternal.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentViewInternal.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateShadow()
	}

    // Route all subviews into the clipping content container, except the container itself
    public override func addSubview(_ view: UIView) {
        if view === contentViewInternal {
            super.addSubview(view)
        } else {
            contentViewInternal.addSubview(view)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        contentViewInternal.layer.cornerRadius = Constants.cornerRadius
        if showsShadow {
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Constants.cornerRadius).cgPath
        }
    }

	public override func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		backgroundColor = collection.css.getColor(.fill, selectors: [.hcCardView, .background], for: nil) ?? .white
	}

    private func updateShadow() {
        if showsShadow {
            // Approximate: 0 0 8px rgba(0,0,0,0.2) + 0 4px 4px rgba(0,0,0,0.25)
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.45
            layer.shadowRadius = 4
            layer.shadowOffset = CGSize(width: 0, height: 4)
        } else {
            layer.shadowOpacity = 0
            layer.shadowRadius = 0
            layer.shadowOffset = .zero
        }
    }
}
