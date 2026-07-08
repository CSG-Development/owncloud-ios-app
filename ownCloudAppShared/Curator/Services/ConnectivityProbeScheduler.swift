import Foundation

/// Foreground periodic tick for connectivity probes. The loop runs whenever the app is
/// active; host screen, network, and paths are checked before each round.
final class ConnectivityProbeScheduler {
	struct Environment: Equatable {
		var networkReachable: Bool
		var hasConfiguredPaths: Bool
	}

	let intervalSeconds: TimeInterval = 30

	private(set) var hostScreenActive = false
	private(set) var isForeground = false
	private(set) var pendingForegroundDelay = false
	private(set) var pendingImmediateProbe = false
	private var loopTask: Task<Void, Never>?

	var isRunning: Bool { loopTask != nil }

	func reset() {
		stop()
		hostScreenActive = false
		isForeground = false
		pendingForegroundDelay = false
		pendingImmediateProbe = false
	}

	func setHostScreenActive(_ active: Bool) {
		hostScreenActive = active
	}

	func setAppForeground(_ foreground: Bool) {
		let wasForeground = isForeground
		isForeground = foreground
		if foreground, !wasForeground {
			pendingImmediateProbe = true
			pendingForegroundDelay = false
		}
		if !foreground {
			pendingForegroundDelay = false
			pendingImmediateProbe = false
		}
	}

	func scheduleImmediateProbeOnNetworkRestore() {
		pendingImmediateProbe = true
		pendingForegroundDelay = false
	}

	func canRunPeriodicProbe(in environment: Environment) -> Bool {
		hostScreenActive
			&& isForeground
			&& environment.networkReachable
			&& environment.hasConfiguredPaths
	}

	func reconcile(
		log: (String) -> Void,
		runRound: @escaping @Sendable () async -> Void
	) async {
		guard isForeground else {
			if isRunning { log("probe loop stopping (foreground=false)") }
			stop()
			return
		}

		if pendingImmediateProbe {
			pendingImmediateProbe = false
			restart(initialDelay: 0, log: log, runRound: runRound)
			return
		}

		guard loopTask == nil else { return }

		let delay = pendingForegroundDelay ? intervalSeconds : 0
		pendingForegroundDelay = false
		restart(initialDelay: delay, log: log, runRound: runRound)
	}

	func stop() {
		loopTask?.cancel()
		loopTask = nil
	}

	private func restart(
		initialDelay: TimeInterval,
		log: (String) -> Void,
		runRound: @escaping @Sendable () async -> Void
	) {
		stop()
		log("probe loop started (initialDelay=\(Int(initialDelay))s interval=\(Int(intervalSeconds))s)")
		loopTask = Task {
			if initialDelay > 0 {
				try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
				guard !Task.isCancelled else { return }
			}
			while !Task.isCancelled {
				await runRound()
				guard !Task.isCancelled else { break }
				try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
			}
		}
	}
}
