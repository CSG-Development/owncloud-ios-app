import Foundation
import UIKit

/// Main-host connectivity monitor: while the host screen is alive and foregrounded, evaluate
/// device paths every 30 s using the current-path-first probe rules.
public final actor ConnectionPingMonitor {
	public static let shared = ConnectionPingMonitor()

	private let intervalSeconds: TimeInterval = 30
	private var connectivityCoordinator: ConnectivityStateCoordinator?

	private var loopTask: Task<Void, Never>?
	private var hostScreenActive = false
	private var isForeground = false
	private var isReachable = true
	private var pendingForegroundDelay = false
	private var pendingImmediateProbe = false
	private var lifecycleObserversInstalled = false
	private var reachability: ReachabilityObserving?
	private var preferences: HCPreferences?

	public init() {}

	public func configure(
		preferences: HCPreferences,
		reachability: ReachabilityObserving,
		connectivityCoordinator: ConnectivityStateCoordinator
	) {
		self.preferences = preferences
		self.reachability = reachability
		self.connectivityCoordinator = connectivityCoordinator
		isReachable = reachability.currentState.isReachable
	}

	/// Stops probing and clears pending probe state (logout).
	public func reset() {
		stopLoop()
		pendingForegroundDelay = false
		pendingImmediateProbe = false
	}

	public func installLifecycleObserversIfNeeded() {
		guard !lifecycleObserversInstalled else { return }
		lifecycleObserversInstalled = true

		NotificationCenter.default.addObserver(
			forName: UIApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			Task { await self?.setForeground(true) }
		}
		NotificationCenter.default.addObserver(
			forName: UIApplication.willResignActiveNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			Task { await self?.setForeground(false) }
		}

		Task { [weak self] in
			await self?.setForeground(true)
		}
	}

	public func setHostScreenActive(_ active: Bool) async {
		hostScreenActive = active
		if active {
			pendingForegroundDelay = true
		}
		await reconcile()
	}

	/// Re-evaluates the probe loop after cold-launch bootstrap completes.
	public func resumeAfterBootstrap() async {
		await reconcile()
	}

	public func setNetworkReachable(_ reachable: Bool) async {
		let wasReachable = isReachable
		isReachable = reachable
		await connectivityCoordinator?.setNetworkReachable(reachable)
		if reachable && !wasReachable && hostScreenActive && isForeground {
			pendingImmediateProbe = true
			pendingForegroundDelay = false
		}
		await reconcile()
	}

	/// Interface type changed (e.g. WiFi → cellular). Schedules an immediate probe round.
	public func setNetworkState(_ state: NetworkState) async {
		let interfaceChanged = lastObservedInterface.map { $0 != state.interface } ?? false
		lastObservedInterface = state.interface
		let wasReachable = isReachable
		isReachable = state.isReachable
		await connectivityCoordinator?.setNetworkReachable(state.isReachable)
		if interfaceChanged && hasConfiguredPaths {
			pendingImmediateProbe = true
			pendingForegroundDelay = false
		} else if state.isReachable && !wasReachable && hostScreenActive && isForeground {
			pendingImmediateProbe = true
			pendingForegroundDelay = false
		}
		await reconcile()
	}

	private var lastObservedInterface: NetworkState.Interface?

	private func setForeground(_ foreground: Bool) async {
		let wasForeground = isForeground
		isForeground = foreground
		if foreground && !wasForeground {
			pendingForegroundDelay = true
		}
		if !foreground {
			pendingForegroundDelay = false
			pendingImmediateProbe = false
		}
		await reconcile()
	}

	private var shouldProbe: Bool {
		hostScreenActive && isForeground && isReachable && hasConfiguredPaths
	}

	private var hasConfiguredPaths: Bool {
		guard let preferences else { return false }
		return preferences.currentConnectedDevice != nil
	}

	private func reconcile() async {
		guard hostScreenActive && isForeground else {
			stopLoop()
			return
		}

		guard isReachable else {
			stopLoop()
			return
		}

		guard hasConfiguredPaths else {
			stopLoop()
			return
		}

		guard await connectivityCoordinator?.isBootstrapComplete == true else {
			stopLoop()
			return
		}

		if pendingImmediateProbe {
			pendingImmediateProbe = false
			restartLoop(initialDelay: 0)
			return
		}

		guard loopTask == nil else { return }

		let delay = pendingForegroundDelay ? intervalSeconds : 0
		pendingForegroundDelay = false
		restartLoop(initialDelay: delay)
	}

	private func restartLoop(initialDelay: TimeInterval) {
		stopLoop()
		loopTask = Task { [weak self] in
			guard let self else { return }
			if initialDelay > 0 {
				try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
				guard !Task.isCancelled else { return }
			}
			while !Task.isCancelled {
				await self.runProbeRound()
				guard !Task.isCancelled else { break }
				try? await Task.sleep(nanoseconds: UInt64(await self.intervalSeconds * 1_000_000_000))
			}
		}
	}

	private func stopLoop() {
		loopTask?.cancel()
		loopTask = nil
	}

	private func runProbeRound() async {
		guard shouldProbe else { return }
		await connectivityCoordinator?.evaluateConfiguredPaths(localPathsAllowed: localPathsAllowed)
	}

	private var localPathsAllowed: Bool {
		reachability?.currentState.allowsLocalPaths ?? true
	}
}
