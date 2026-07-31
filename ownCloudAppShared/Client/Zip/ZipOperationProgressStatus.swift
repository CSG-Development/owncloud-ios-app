import Foundation

/// Controls the status label shown above zip progress.
///
/// Ticket UX uses a single Compressing… / Decompressing… label for the whole run.
/// Set `showsDetailedPhaseStatus` to `true` to restore Preparing / Downloading / Saving / etc.
public enum ZipOperationProgressStatus {
	/// When `true`, progress labels reflect the active phase (Preparing, Downloading, …).
	/// When `false` (default), only Compressing… / Decompressing… are shown while the job runs.
	public static var showsDetailedPhaseStatus = false

	public static func displayText(for kind: ZipOperationRecord.Kind, detailedStatus: String) -> String {
		guard !showsDetailedPhaseStatus else {
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
