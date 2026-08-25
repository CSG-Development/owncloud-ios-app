import SnapKit
import UIKit
import UniformTypeIdentifiers
import ownCloudSDK

/// Single in-progress file operation row (file icon, filename, status, progress, cancel).
final class FileListActivityActionRowView: UIView {

	static let horizontalInset: CGFloat = 16
	static let contentSpacing: CGFloat = 16
	static let iconSize: CGFloat = 29
	static let progressHeight: CGFloat = 4
	static let cancelButtonHeight: CGFloat = 46
	static let preferredHeight: CGFloat = 105

	var onCancel: (() -> Void)?
	private(set) var recordID: String = ""

	private let iconImageView = UIImageView()
	private let contentStack = UIStackView()
	private let titleLabel = UILabel()
	private let statusLabel = UILabel()
	private let progressView = UIProgressView(progressViewStyle: .default)
	private let cancelButtonContainer = UIView()
	private let cancelButton = UIButton(type: .system)
	private var configuredDocumentName: String?
	private var configuredKind: ZipOperationRecord.Kind = .compress

	override init(frame: CGRect) {
		super.init(frame: frame)

		iconImageView.contentMode = .scaleAspectFit
		iconImageView.setContentHuggingPriority(.required, for: .horizontal)
		iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

		contentStack.axis = .vertical
		contentStack.alignment = .fill
		contentStack.distribution = .fill

		titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
		titleLabel.numberOfLines = 1
		titleLabel.lineBreakMode = .byTruncatingMiddle

		statusLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
		statusLabel.numberOfLines = 1
		statusLabel.lineBreakMode = .byTruncatingTail

		cancelButton.setTitle(HCL10n.Common.cancel, for: .normal)
		cancelButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .footnote)
		cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
		cancelButton.setContentHuggingPriority(.required, for: .horizontal)
		cancelButton.setContentCompressionResistancePriority(.required, for: .horizontal)

		cancelButtonContainer.addSubview(cancelButton)

		contentStack.addArrangedSubview(titleLabel)
		contentStack.addArrangedSubview(statusLabel)
		contentStack.addArrangedSubview(progressView)
		contentStack.addArrangedSubview(cancelButtonContainer)

		addSubview(iconImageView)
		addSubview(contentStack)

		iconImageView.snp.makeConstraints {
			$0.leading.equalToSuperview().offset(Self.horizontalInset)
			$0.centerY.equalTo(contentStack)
			$0.size.equalTo(Self.iconSize)
		}

		contentStack.snp.makeConstraints {
			$0.leading.equalTo(iconImageView.snp.trailing).offset(Self.contentSpacing)
			$0.trailing.equalToSuperview().inset(Self.horizontalInset)
			$0.top.bottom.equalToSuperview()
		}

		progressView.snp.makeConstraints {
			$0.height.equalTo(Self.progressHeight)
		}

		cancelButton.snp.makeConstraints {
			$0.leading.top.bottom.equalToSuperview()
			$0.height.equalTo(Self.cancelButtonHeight)
		}

		contentStack.setCustomSpacing(4, after: titleLabel)
		contentStack.setCustomSpacing(8, after: statusLabel)
		contentStack.setCustomSpacing(8, after: progressView)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(with record: ZipOperationRecord) {
		recordID = record.id
		configuredDocumentName = record.documentName
		configuredKind = record.kind
		titleLabel.text = record.documentName
		statusLabel.text = record.displayStatusText
		iconImageView.image = Self.fileTypeIcon(for: record.documentName, kind: record.kind)

		let progress = Float(record.fractionCompleted)
		if abs(progressView.progress - progress) > 0.001 {
			progressView.setProgress(progress, animated: progress > progressView.progress)
		} else {
			progressView.progress = progress
		}
	}

	func applyColors(isDark: Bool) {
		titleLabel.textColor = HCColor.Content.textPrimary(isDark)
		statusLabel.textColor = HCColor.Content.textSecondary(isDark)
		progressView.progressTintColor = HCColor.Interaction.cta(isDark)
		progressView.trackTintColor = HCColor.Content.border2(isDark)
		cancelButton.setTitleColor(HCColor.Interaction.primarySolidNormal(isDark), for: .normal)

		if let documentName = configuredDocumentName {
			iconImageView.image = Self.fileTypeIcon(for: documentName, kind: configuredKind)
		}
	}

	@objc private func cancelTapped() {
		onCancel?()
	}

	private static func fileTypeIcon(for documentName: String, kind: ZipOperationRecord.Kind) -> UIImage? {
		let size = CGSize(width: iconSize, height: iconSize)
		let ext = (documentName as NSString).pathExtension
		let iconName: String

		if kind == .decompress, ext.isEmpty {
			iconName = "folder"
		} else if !ext.isEmpty,
		          let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType,
		          let name = OCItem.iconName(for: mimeType) {
			iconName = name
		} else {
			iconName = "file"
		}

		return Theme.shared.image(for: iconName, size: size)
	}
}
