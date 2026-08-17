import Foundation

/// Controls the status label shown above zip progress.
///
/// Ticket UX uses a single Compressing… / Decompressing… label for the whole run
/// (except Waiting… when queued behind another job).
public enum ZipOperationProgressStatus {
	public static func displayText(for kind: ZipOperationRecord.Kind, detailedStatus: String) -> String {
		if detailedStatus == HCL10n.ZipAction.Progress.waiting {
			return detailedStatus
		}
		switch kind {
		case .compress:
			return HCL10n.ZipAction.Progress.compressing
		case .decompress:
			return HCL10n.ZipAction.Progress.decompressing
		}
	}
}
