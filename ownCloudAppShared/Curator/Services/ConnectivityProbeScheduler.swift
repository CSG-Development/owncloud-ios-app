import Foundation

/// Host-screen periodic path probe loop (formerly part of `ConnectionPingMonitor`).
final class ConnectivityProbeScheduler {
	struct Environment: Equatable {
		var networkReachable: Bool
		var hasConfiguredPaths: Bool
		var isBootstrapComplete: Bool
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
		if active {
			pendingForegroundDelay = true
		}
	}

	func setAppForeground(_ foreground: Bool) {
		let wasForeground = isForeground
		isForeground = foreground
		if foreground, !wasForeground {
			pendingForegroundDelay = true
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
			&& environment.isBootstrapComplete
	}

	func reconcile(
		environment: Environment,
		log: (String) -> Void,
		runRound: @escaping @Sendable () async -> Void
	) async {
		guard hostScreenActive, isForeground else {
			if isRunning { log("probe loop stopping (host=\(hostScreenActive) fg=\(isForeground))") }
			stop()
			return
		}
		guard environment.networkReachable else {
			if isRunning { log("probe loop stopping (network down)") }
			stop()
			return
		}
		guard environment.hasConfiguredPaths else {
			if isRunning { log("probe loop stopping (no configured paths)") }
			stop()
			return
		}
		guard environment.isBootstrapComplete else {
			if isRunning { log("probe loop stopping (bootstrap incomplete)") }
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
