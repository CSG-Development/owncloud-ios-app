import Foundation
import ownCloudSDK

/// Errors surfaced when catalog reload / path recovery handlers fail.
public enum ConnectivityPathRecoveryError: Error, Sendable, LocalizedError {
	case catalogReloadFailed(String)

	public var errorDescription: String? {
		switch self {
			case .catalogReloadFailed(let detail):
				return "Catalog reload failed: \(detail)"
		}
	}
}
