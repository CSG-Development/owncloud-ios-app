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
		to: DeviceAccessState,
		policy: ConnectivityAccessPolicy
	) {
		guard from != to else { return }
		log("device \(from)→\(to) policy=\(policy)")
	}

	static func deviceAccessSuppressed(
		_ state: DeviceAccessState,
		policy: ConnectivityAccessPolicy,
		reason: String
	) {
		log("device access \(state) ignored (\(reason) policy=\(policy))")
	}

	static func recoveryFailure(_ step: String, error: Error) {
		log("recovery \(step) failed: \(error.localizedDescription)")
	}

	static func probeResult(
		_ result: PathConnectivityProbeResult,
		pathCount: Int,
		currentPathKey: String?,
		localPathsAllowed: Bool
	) {
		log(
			"probe result=\(ConnectivityProbeResultLabel.label(result)) "
				+ "paths=\(pathCount) current=\(currentPathKey ?? "none") "
				+ "localAllowed=\(localPathsAllowed)"
		)
	}
}
