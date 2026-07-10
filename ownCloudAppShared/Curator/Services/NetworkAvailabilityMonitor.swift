import Foundation

/// Which message the connectivity banner should display.
public enum NetworkAvailabilityToastKind: Sendable, Equatable {
	case findingNetwork
	case noInternet
	case connectionLost
}

/// Holds banner visibility for the main host screen network monitor.
/// Dismiss (×) is view-level only — the next probe/state emit may show the banner again.
public final actor NetworkAvailabilityMonitor {
	public static let shared = NetworkAvailabilityMonitor()

	private var visibleKind: NetworkAvailabilityToastKind?
	private var visibilityHandler: (@MainActor (NetworkAvailabilityToastKind?) -> Void)?

	public init() {}

	public func observeToastVisibility(_ handler: @escaping @MainActor (NetworkAvailabilityToastKind?) -> Void) {
		visibilityHandler = handler
		let snapshot = visibleKind
		Task { @MainActor in handler(snapshot) }
	}

	/// Single entry point for coordinator-driven visibility. Pass `nil` to hide.
	public func setVisibility(_ kind: NetworkAvailabilityToastKind?) {
		guard visibleKind != kind else { return }
		let previousVisible = visibleKind
		visibleKind = kind
		if let kind {
			Self.log("banner show \(ConnectivityBannerPresenter.bannerLabel(kind))")
		} else if previousVisible != nil {
			Self.log("banner hide (was \(ConnectivityBannerPresenter.bannerLabel(previousVisible)))")
		}
		emitVisibility(kind)
	}

	/// Clears banner state on logout.
	public func reset() {
		setVisibility(nil)
	}

	/// User tapped the dismiss (×) button. Only applies to non-blocking snackbars.
	public func dismiss() {
		guard let dismissed = visibleKind,
		      dismissed == .findingNetwork || dismissed == .noInternet else { return }
		visibleKind = nil
		Self.log("banner user dismissed \(ConnectivityBannerPresenter.bannerLabel(dismissed))")
		emitVisibility(nil)
	}

	private func emitVisibility(_ kind: NetworkAvailabilityToastKind?) {
		guard let handler = visibilityHandler else { return }
		Task { @MainActor in handler(kind) }
	}

	private static func log(_ message: String) {
		Log.debug("[STX-CONN]: \(message)")
	}
}
