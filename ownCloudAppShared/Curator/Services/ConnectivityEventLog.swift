import Foundation

/// Structured connectivity logging with lazy message evaluation.
enum ConnectivityEventLog {
	static func log(_ message: @autoclosure () -> String) {
		Log.debug("[STX-CONN]: \(message())")
	}

	static func stateTransition(
		from: ConnectivityState,
		to: ConnectivityState,
		reason: String
	) {
		guard from != to else { return }
		log("state \(from)→\(to) (\(reason))")
	}

	static func deviceAccess(
		from: DeviceAccessState,
		to: DeviceAccessState
	) {
		guard from != to else { return }
		log("device \(from)→\(to)")
	}

	static func deviceAccessSuppressed(
		_ state: DeviceAccessState,
		reason: String
	) {
		log("device access \(state) ignored (\(reason))")
	}

	static func recoveryFailure(_ step: String, error: Error) {
		log("recovery \(step) failed: \(error.localizedDescription)")
	}

	static func probeOutcome(
		_ outcome: PathProbeOutcome,
		pathCount: Int,
		currentPathKey: String?,
		localPathsAllowed: Bool
	) {
		let label: String
		switch outcome {
			case .currentIsBest:   label = "currentIsBest"
			case .betterPath:      label = "betterPath"
			case .noneReachable:   label = "noneReachable"
		}
		log(
			"probe outcome=\(label) paths=\(pathCount) current=\(currentPathKey ?? "none") "
				+ "localAllowed=\(localPathsAllowed)"
		)
	}
}
