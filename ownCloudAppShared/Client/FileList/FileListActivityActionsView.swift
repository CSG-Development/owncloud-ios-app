import SnapKit
import UIKit

/// Expandable body of the Activity-in-progress card: per-operation rows when expanded.
final class FileListActivityActionsView: UIView {

	static let bodyBottomInset: CGFloat = 14
	static let rowSpacing: CGFloat = 12

	var onCancelRecord: ((ZipOperationRecord) -> Void)?

	private let bodyStack = UIStackView()
	private let operationsStack = UIStackView()
	private var isDark = false
	private var isExpanded = false
	private var records: [ZipOperationRecord] = []

	override init(frame: CGRect) {
		super.init(frame: frame)

		clipsToBounds = true
		setContentCompressionResistancePriority(.defaultLow, for: .vertical)

		bodyStack.axis = .vertical
		bodyStack.spacing = Self.rowSpacing
		bodyStack.alignment = .fill
		bodyStack.distribution = .fill
		bodyStack.isLayoutMarginsRelativeArrangement = true
		bodyStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: Self.bodyBottomInset, right: 0)
		bodyStack.setContentHuggingPriority(.required, for: .vertical)
		bodyStack.setContentCompressionResistancePriority(.required, for: .vertical)

		operationsStack.axis = .vertical
		operationsStack.spacing = Self.rowSpacing
		operationsStack.isHidden = true

		addSubview(bodyStack)
		bodyStack.addArrangedSubview(operationsStack)

		bodyStack.snp.makeConstraints {
			$0.top.leading.trailing.equalToSuperview()
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(records: [ZipOperationRecord], expanded: Bool, animated: Bool = false) {
		guard records.count != 1 else {
			if let record = records.first {
				configureSingle(record, animated: animated)
			}
			return
		}

		self.records = records
		let expansionChanged = isExpanded != expanded
		isExpanded = expanded

		let shouldAnimateExpansion = animated && expansionChanged

		if shouldAnimateExpansion {
			if expanded {
				UIView.performWithoutAnimation {
					self.rebuildOperationRowsIfNeeded()
					self.operationsStack.isHidden = false
					self.operationsStack.alpha = 0
					self.setNeedsLayout()
					self.layoutIfNeeded()
				}
				UIView.animate(
					withDuration: 0.28,
					delay: 0,
					options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
				) {
					self.operationsStack.alpha = 1
				}
			} else {
				UIView.animate(
					withDuration: 0.28,
					delay: 0,
					options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
				) {
					self.operationsStack.alpha = 0
				} completion: { finished in
					guard finished, !self.isExpanded else { return }
					self.operationsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
					self.operationsStack.isHidden = true
					self.operationsStack.alpha = 1
				}
			}
		} else {
			UIView.performWithoutAnimation {
				if self.isExpanded {
					self.rebuildOperationRowsIfNeeded()
					self.operationsStack.isHidden = false
					self.operationsStack.alpha = 1
				} else {
					self.operationsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
					self.operationsStack.isHidden = true
					self.operationsStack.alpha = 1
				}
				self.setNeedsLayout()
				self.layoutIfNeeded()
			}
		}
	}

	/// Single in-flight operation: show the row directly (no collapsible header wrapper).
	func configureSingle(_ record: ZipOperationRecord, animated: Bool = false) {
		isExpanded = false
		records = [record]

		let apply = {
			self.rebuildOperationRowsIfNeeded()
			self.operationsStack.isHidden = false
			self.operationsStack.alpha = 1
			self.setNeedsLayout()
			self.layoutIfNeeded()
		}

		if animated {
			UIView.animate(
				withDuration: 0.28,
				delay: 0,
				options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
				animations: apply
			)
		} else {
			UIView.performWithoutAnimation(apply)
		}
	}

	func applyColors(isDark: Bool) {
		self.isDark = isDark

		for case let row as FileListActivityActionRowView in operationsStack.arrangedSubviews {
			row.applyColors(isDark: isDark)
		}
	}

	static func preferredHeight(expanded: Bool, operationCount: Int) -> CGFloat {
		if operationCount == 1 {
			return FileListActivityActionRowView.preferredHeight
		}
		guard expanded else { return 0 }
		let count = max(operationCount, 0)
		let stack = CGFloat(count) * FileListActivityActionRowView.preferredHeight
			+ CGFloat(max(count - 1, 0)) * rowSpacing
		return stack + bodyBottomInset
	}

	private func rebuildOperationRowsIfNeeded() {
		let existing = operationsStack.arrangedSubviews.compactMap { $0 as? FileListActivityActionRowView }
		let existingIDs = existing.map(\.recordID)
		let nextIDs = records.map(\.id)
		if existingIDs == nextIDs {
			for (index, record) in records.enumerated() {
				existing[index].configure(with: record)
				existing[index].applyColors(isDark: isDark)
				existing[index].onCancel = { [weak self, weak record] in
					guard let self, let record else { return }
					self.onCancelRecord?(record)
				}
			}
			return
		}

		operationsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
		for record in records {
			let row = FileListActivityActionRowView()
			row.configure(with: record)
			row.applyColors(isDark: isDark)
			row.onCancel = { [weak self, weak record] in
				guard let self, let record else { return }
				self.onCancelRecord?(record)
			}
			operationsStack.addArrangedSubview(row)
		}
	}
}
