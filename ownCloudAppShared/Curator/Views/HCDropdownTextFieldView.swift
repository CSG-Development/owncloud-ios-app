import UIKit
import SnapKit

fileprivate enum Constants {
    static let maxDropdownHeight: CGFloat = 320
	static let optionHeight: CGFloat = 56
	static let optionHorizontalPadding: CGFloat = 12
}

public final class HCDropdownTextFieldView: HCTextFieldView, UITextFieldDelegate {
	// MARK: - Public API
    public override var title: String? {
		didSet {
			borderView.title = title
			updateAppearance()
		}
	}

    public override var placeholder: String? {
		didSet {
			updateAppearance()
		}
	}
	public var items: [String] = [] {
		didSet {
			rebuildOptions()
			updateDropdownHeight()
			if let selectedIndex, items.indices.contains(selectedIndex) {
				textField.text = items[selectedIndex]
			}
		}
	}

	public var selectedIndex: Int? {
		didSet {
			guard let selectedIndex, items.indices.contains(selectedIndex) else { return }
			textField.text = items[selectedIndex]
			updateSelectedState()
		}
	}

    public var onSelection: ((_ index: Int, _ value: String) -> Void)?
    public var onFooterTap: (() -> Void)?

	// MARK: - UI Elements
	private lazy var chevronButton: UIButton = {
		let button = UIButton(type: .custom)
		button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
		button.tintColor = tintColor
		button.addTarget(self, action: #selector(toggleDropdown), for: .touchUpInside)
		return button
	}()

private let dropdownCard = HCCardView(frame: .zero)
	private let scrollView = UIScrollView()
	private let stackView: UIStackView = {
		let sv = UIStackView()
		sv.axis = .vertical
		sv.spacing = 0
		sv.alignment = .fill
		return sv
	}()

    private var dropdownHeightConstraint: Constraint?
    public weak var dropdownHostView: UIView?
    private weak var installedHostView: UIView?
	private var isExpanded: Bool = false
	private var outsideTapRecognizer: UITapGestureRecognizer?

	// MARK: - Lifecycle
	public override init(frame: CGRect) {
		super.init(frame: frame)

		commonDropdownInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)

		commonDropdownInit()
	}

	private func commonDropdownInit() {
		// Use chevron in the right view and prevent the default clear button behavior
		textField.rightView = chevronButton
		textField.rightViewMode = .always
		textField.delegate = self
		textField.tintColor = .clear // hide caret if it ever becomes first responder

		// Reuse HCTextFieldView's placeholder styling machinery
		addThemeApplier { [weak self] _, collection, _ in
			guard let self = self else { return }
			var styled = AttributedString(self.placeholder ?? "")
			styled.foregroundColor = collection.css.getColor(.stroke, selectors: [.placeholder], for: self)
			styled.font = UIFont.systemFont(ofSize: 16)
			self.textField.attributedPlaceholder = NSAttributedString(styled)
		}

		clipsToBounds = false // allow the dropdown to overflow below

		// Prepare dropdown card container
		dropdownCard.showsShadow = true
		dropdownCard.isHidden = true
		dropdownCard.alpha = 0

		dropdownCard.addSubview(scrollView)
		scrollView.snp.makeConstraints { make in
			make.leading.trailing.equalToSuperview()
			make.top.bottom.equalToSuperview().inset(8)
		}

		scrollView.delaysContentTouches = false
		scrollView.canCancelContentTouches = true

		scrollView.addSubview(stackView)
		stackView.snp.makeConstraints { make in
			make.edges.equalToSuperview()
			make.width.equalTo(scrollView.snp.width)
		}

		rebuildOptions()
	}

    private func isAncestor(_ ancestor: UIView, of view: UIView) -> Bool {
        var v: UIView? = view
        while let current = v {
            if current === ancestor { return true }
            v = current.superview
        }
        return false
    }

    private func rebuildOptions() {
        for view in stackView.arrangedSubviews { view.removeFromSuperview() }
        for (index, title) in items.enumerated() {
            let row = DropdownOptionRow(title: title, index: index, selectable: true)
            row.onTap = { [weak self] idx in
                guard let self, let idx else { return }
                self.selectedIndex = idx
                self.onSelection?(idx, self.items[idx])
                self.collapseDropdown()
            }
            row.showSeparator = true
            stackView.addArrangedSubview(row)
        }

        let footer = DropdownOptionRow(title: "I don’t see my Curator", index: nil, selectable: true)
		footer.onTap = { [weak self] idx in
			self?.collapseDropdown()
			self?.onFooterTap?()
		}
        footer.showSeparator = false
        stackView.addArrangedSubview(footer)
        updateSelectedState()
    }

    private func updateSelectedState() {
        for view in stackView.arrangedSubviews {
            if let row = view as? DropdownOptionRow {
                row.isSelected = (row.index == selectedIndex)
            }
        }
    }

    private func updateDropdownHeight() {
        let contentHeight = CGFloat(items.count + 1) * Constants.optionHeight
		let targetHeight = min(contentHeight, Constants.maxDropdownHeight)
        dropdownHeightConstraint?.update(offset: targetHeight + 40) // account for 20pt insets top/bottom
        installedHostView?.layoutIfNeeded()
	}

	// MARK: - UITextFieldDelegate
	public func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
		// Intercept to toggle dropdown instead of showing the keyboard
		if isExpanded {
			collapseDropdown()
		} else {
			expandDropdown()
		}
		return false
	}

	// MARK: - Theme
	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		let chevronColor = collection.css.getColor(.stroke, selectors: [.text], for: self)
		chevronButton.tintColor = chevronColor

        super.applyThemeCollection(theme: theme, collection: collection, event: event)

		rebuildOptions()
	}

	// MARK: - Actions
	@objc private func toggleDropdown() {
		if isExpanded {
			collapseDropdown()
		} else {
			expandDropdown()
		}
	}

	@objc private func didTapOption(_ sender: UIButton) {
		let index = sender.tag
		guard items.indices.contains(index) else { return }
		selectedIndex = index
		onSelection?(index, items[index])
		collapseDropdown()
	}

	private func expandDropdown() {
		guard isExpanded == false else { return }
		isExpanded = true
        // Determine host view (must be provided by caller)
        guard let hostView = dropdownHostView else { return }

        // Ensure hostView is an ancestor so we can anchor via constraints and scroll together
        guard isAncestor(hostView, of: borderView) else { return }

        // Add dropdown directly to the host view
        hostView.addSubview(dropdownCard)

        // Anchor dropdown under the field using constraints (keeps size/position synced)
        dropdownCard.snp.remakeConstraints { make in
            make.top.equalTo(borderView.snp.bottom).offset(4)
            make.leading.equalTo(borderView.snp.leading)
            make.trailing.equalTo(borderView.snp.trailing)
            dropdownHeightConstraint = make.height.equalTo(0).constraint
        }

        updateDropdownHeight()
        updateChevron(isExpanded: true)
        dropdownCard.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.dropdownCard.alpha = 1
        }
        self.installedHostView = hostView
        installOutsideTapRecognizer()
	}

	private func collapseDropdown() {
		guard isExpanded == true else { return }
		isExpanded = false
        updateChevron(isExpanded: false)
        UIView.animate(withDuration: 0.2, animations: {
            self.dropdownCard.alpha = 0
        }) { _ in
            self.dropdownCard.isHidden = true
            self.dropdownCard.removeFromSuperview()
            self.installedHostView = nil
        }
        removeOutsideTapRecognizer()
	}

	private func updateChevron(isExpanded: Bool) {
		let imageName = isExpanded ? "chevron.up" : "chevron.down"
		chevronButton.setImage(UIImage(systemName: imageName), for: .normal)
	}

	private func installOutsideTapRecognizer() {
		guard outsideTapRecognizer == nil else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleOutsideTap(_:)))
        recognizer.cancelsTouchesInView = false
        outsideTapRecognizer = recognizer
        installedHostView?.addGestureRecognizer(recognizer)
	}

	private func removeOutsideTapRecognizer() {
        if let recognizer = outsideTapRecognizer {
            installedHostView?.removeGestureRecognizer(recognizer)
            outsideTapRecognizer = nil
        }
	}

	@objc private func handleOutsideTap(_ recognizer: UITapGestureRecognizer) {
		guard recognizer.state == .ended else { return }
        guard let hostView = installedHostView else { return }
        let location = recognizer.location(in: hostView)
        let isInsideDropdown = dropdownCard.frame.contains(location)
        let anchorRect = borderView.convert(borderView.bounds, to: hostView)
        let isInsideAnchor = anchorRect.contains(location)
		if !(isInsideDropdown || isInsideAnchor) {
			collapseDropdown()
		}
	}
}

// MARK: - DropdownOptionRow
private final class DropdownOptionRow: ThemeCSSView {
    var index: Int?
    var onTap: ((Int?) -> Void)?
    var isSelected: Bool = false { didSet { updateSelectionAppearance() } }
    var showSeparator: Bool = false { didSet { separator.isHidden = !showSeparator } }

    private let selectable: Bool
    private let button = UIButton(type: .custom)
    private let separator = UIView()

    init(title: String, index: Int?, selectable: Bool) {
        self.index = index
        self.selectable = selectable
        super.init(frame: .zero)

        addSubview(button)
        addSubview(separator)

        button.setTitle(title, for: .normal)
		button.titleLabel?.font = UIFont.systemFont(ofSize: 16)
		let textColor = Theme.shared.activeCollection.css.getColor(.stroke, selectors: [.hcDropdownView], for: nil)
		button.setTitleColor(textColor, for: .normal)
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: Constants.optionHorizontalPadding, bottom: 0, right: Constants.optionHorizontalPadding)
        button.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(Constants.optionHeight)
        }

        separator.backgroundColor = .separator
        separator.snp.makeConstraints { make in
            make.top.equalTo(button.snp.bottom)
            make.leading.trailing.equalTo(button)
            make.height.equalTo(1)
            make.bottom.equalToSuperview()
        }

        if selectable {
            button.addTarget(self, action: #selector(tap), for: .touchUpInside)
            button.isUserInteractionEnabled = true
        } else {
            button.isUserInteractionEnabled = true
        }

        updateSelectionAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	public override func applyThemeCollection(
		theme: Theme,
		collection: ThemeCollection,
		event: ThemeEvent
	) {
		super.applyThemeCollection(theme: theme, collection: collection, event: event)

		separator.backgroundColor = collection.css.getColor(.fill, selectors: [.separator], for: nil) ?? .white
	}

    private func updateSelectionAppearance() {
		let selectedColor = Theme.shared.activeCollection.css.getColor(.fill, selectors: [.hcDropdownView], for: nil) ?? .white

        backgroundColor = isSelected ? selectedColor : .clear
    }

    @objc private func tap() {
        guard selectable else { return }
		onTap?(index)
    }
}
