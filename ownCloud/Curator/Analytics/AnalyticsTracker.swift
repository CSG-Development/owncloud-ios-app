final class AnalyticsTracker: AnalyticsTrackerType {
	static let shared = AnalyticsTracker()

	private let trackers: [AnalyticsTrackerType]

	init() {
		trackers = [
			TelemetryAnalyticsTracker()
		]
	}

	func setup() {
		// Do nothing
	}

	func track(_ event: AnalyticsEvent) {
		trackers.forEach { $0.track(event) }
	}
}
