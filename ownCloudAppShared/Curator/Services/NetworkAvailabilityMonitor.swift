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
	private var pendingKind: NetworkAvailabilityToastKind?
	private var showTask: Task<Void, Never>?
	private var visibilityHandler: (@MainActor (NetworkAvailabilityToastKind?) -> Void)?
	private var visibilityGeneration: UInt = 0

	/// Brief grace so URL switching / fast recovery does not flash the snackbar.
	private let findingNetworkDelaySeconds: TimeInterval = 2
	/// Slightly longer grace before the persistent retry banner appears.
	private let connectionLostDelaySeconds: TimeInterval = 3

	public init() {}

	public func observeToastVisibility(_ handler: @escaping @MainActor (NetworkAvailabilityToastKind?) -> Void) {
		visibilityHandler = handler
		let snapshot = visibleKind
		Task { @MainActor in handler(snapshot) }
	}

	/// Single entry point for coordinator-driven visibility. Pass `nil` to hide.
	public func setVisibility(_ kind: NetworkAvailabilityToastKind?) {
		visibilityGeneration &+= 1
		let generation = visibilityGeneration
		let hadPendingShow = pendingKind != nil
		let previousVisible = visibleKind
		showTask?.cancel()
		showTask = nil
		pendingKind = nil

		guard let kind else {
			let shouldHide = visibleKind != nil || hadPendingShow
			visibleKind = nil
			if shouldHide {
				Self.log(
					"banner hide (was \(Self.bannerLabel(previousVisible))"
						+ (hadPendingShow ? ", cancelled pending" : "") + ")"
				)
				emitVisibility(nil)
			}
			return
		}

		if visibleKind == kind { return }

		let delay = showDelay(for: kind)
		guard delay > 0 else {
			visibleKind = kind
			Self.log("banner show \(Self.bannerLabel(kind)) (immediate)")
			emitVisibility(kind)
			return
		}

		pendingKind = kind
		Self.log("banner schedule \(Self.bannerLabel(kind)) in \(Int(delay))s")
		showTask = Task {
			let nanos = UInt64(delay * 1_000_000_000)
			try? await Task.sleep(nanoseconds: nanos)
			guard !Task.isCancelled else { return }
			await self.commitPendingShow(expected: kind, generation: generation)
		}
	}

	/// Clears banner state on logout.
	public func reset() {
		setVisibility(nil)
	}

	/// User tapped the dismiss (×) button. Only applies to non-blocking snackbars.
	public func dismiss() {
		guard visibleKind == .findingNetwork || visibleKind == .noInternet else { return }
		guard visibleKind != nil else { return }
		visibilityGeneration &+= 1
		showTask?.cancel()
		showTask = nil
		pendingKind = nil
		let dismissed = visibleKind
		visibleKind = nil
		Self.log("banner user dismissed \(Self.bannerLabel(dismissed))")
		emitVisibility(nil)
	}

	private func showDelay(for kind: NetworkAvailabilityToastKind) -> TimeInterval {
		switch kind {
			case .findingNetwork:  return findingNetworkDelaySeconds
			case .connectionLost:  return connectionLostDelaySeconds
			case .noInternet:        return 0
		}
	}

	private func commitPendingShow(expected kind: NetworkAvailabilityToastKind, generation: UInt) {
		guard generation == visibilityGeneration, pendingKind == kind else {
			Self.log(
				"banner show \(Self.bannerLabel(kind)) dropped "
					+ "(gen=\(generation) current=\(visibilityGeneration))"
			)
			return
		}
		pendingKind = nil
		visibleKind = kind
		Self.log("banner show \(Self.bannerLabel(kind)) (after delay)")
		emitVisibility(kind)
	}

	private func emitVisibility(_ kind: NetworkAvailabilityToastKind?) {
		guard let handler = visibilityHandler else { return }
		Task { @MainActor in handler(kind) }
	}

	private static func log(_ message: String) {
		Log.debug("[STX-CONN]: \(message)")
	}

	private static func bannerLabel(_ kind: NetworkAvailabilityToastKind?) -> String {
		switch kind {
			case nil:                 return "hidden"
			case .findingNetwork:      return "findingNetwork"
			case .noInternet:          return "noInternet"
			case .connectionLost:      return "connectionLost"
		}
	}
}
