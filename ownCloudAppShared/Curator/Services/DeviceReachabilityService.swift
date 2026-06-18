import Foundation
import Network
import Combine
import ownCloudSDK
import UIKit

public final actor DeviceReachabilityService {
	/// Source of truth for the current best base URL. Exposed `nonisolated` so callers
	/// (notably the sidebar) can query `currentBaseURL()` synchronously from the main
	/// thread without an actor hop.
	public nonisolated let urlProvider: DeviceReachabilityURLProvider

	/// Owns the remote/local/probes/static state and all path-selection logic. The service
	/// is reachability-aware (it knows the current `wifiAvailable` flag) and threads that
	/// flag into every catalog call.
	private let catalog: DeviceCatalog
	/// Algorithm A pipeline (full reload + reprobe + recalc + availability + mDNS).
	/// Wraps `DirectPathResolver` (Algorithm B) and exposes it via
	/// `attemptDirectResolution(...)`. The facade delegates all probing/discovery
	/// work to this pipeline.
	private let pipeline: DetectionPipeline
	/// Algorithm D — the network-change FSM, foreground gate, cooldown timer and
	/// `detectionsInFlight` reference count. The facade forwards reachability and
	/// app-lifecycle events to it via `coordinator.handle(_:)`.
	private let coordinator: NetworkChangeCoordinator
	/// Backing subject for `events`. `PassthroughSubject` is thread-safe, so we expose it
	/// `nonisolated` and call `send(_:)` directly from any context (actor-isolated or not).
	private nonisolated let eventsSubject = PassthroughSubject<DeviceReachabilityEvent, Never>()

	/// Single typed event channel — see `DeviceReachabilityEvent`. Subscribers should
	/// `.receive(on:)` their preferred queue before touching UI.
	public nonisolated var events: AnyPublisher<DeviceReachabilityEvent, Never> {
		eventsSubject.eraseToAnyPublisher()
	}

	private nonisolated func emit(_ event: DeviceReachabilityEvent) {
		eventsSubject.send(event)
	}
	private var networkChangeCancellable: AnyCancellable?
	private var foregroundCancellable: AnyCancellable?
	private var staticDeviceAddressCancellable: AnyCancellable?
	/// Spec: connection paths cached with a timestamp; expire after 1 hour.
	/// Owned by `PathCacheStore`; persistence (1h TTL → `HCPreferences`) lives there.
	private let pathCacheStore: PathCacheStore
	private let reachability: ReachabilityObserving
	private let remoteAccessService: RemoteAccessService
	private let mdnsService: MDNSService
	private let preferences: HCPreferences
	private let connectivityCoordinator: ConnectivityStateCoordinator?

	public init(
		reachability: ReachabilityObserving,
		remoteAccessService: RemoteAccessService,
		mdnsService: MDNSService,
		preferences: HCPreferences,
		pathProber: PathProber = PathProber(),
		connectivityCoordinator: ConnectivityStateCoordinator? = nil
	) {
		self.reachability = reachability
		self.remoteAccessService = remoteAccessService
		self.mdnsService = mdnsService
		self.preferences = preferences
		self.connectivityCoordinator = connectivityCoordinator
		let pathCacheStore = PathCacheStore(preferences: preferences)
		let catalog = DeviceCatalog()
		self.pathCacheStore = pathCacheStore
		self.catalog = catalog

		urlProvider = DeviceReachabilityURLProvider(preferences: preferences)

		// `eventsSubject` is `nonisolated` so it is safe to reach from any context.
		let subject = self.eventsSubject
		let pipeline = DetectionPipeline(
			pathProber: pathProber,
			pathCacheStore: pathCacheStore,
			catalog: catalog,
			urlProvider: urlProvider,
			mdnsService: mdnsService,
			remoteAccessService: remoteAccessService,
			preferences: preferences,
			reachability: reachability,
			emit: { event in
				subject.send(event)
				if case .pipelineReloadingChanged(let loading) = event {
					Task { await connectivityCoordinator?.setPipelineReloading(loading) }
				}
			}
		)
		self.pipeline = pipeline
		self.coordinator = NetworkChangeCoordinator(
			pipeline: pipeline,
			remoteAccessService: remoteAccessService,
			preferences: preferences,
			emit: { event in subject.send(event) },
			onPathRecoveryNeeded: { [connectivityCoordinator, reachability] in
				let localAllowed = reachability.currentState.allowsLocalPaths
				await connectivityCoordinator?.runPathRecovery(localPathsAllowed: localAllowed)
			}
		)

		// MARK: catalog seeding
		let initialStatic = DetectionPipeline.buildStaticRemoteDevice(from: preferences.staticDeviceAddress)
		Task { [catalog] in await catalog.setStaticRemoteDevice(initialStatic) }

		staticDeviceAddressCancellable = preferences.staticDeviceAddressPublisher
			.removeDuplicates()
			.sink { [weak self] address in
				guard let self else { return }
				Task { await self.handleStaticDeviceAddressChange(address) }
			}

		mdnsService.onUpdate = { [weak self] locals in
			guard let self else { return }
			Task { await self.handleMDNSUpdate(locals) }
		}
	}

	/// Seeds the SDK base URL from the last successful path or bookmark before the first
	/// detection pass, so authenticated cold launch does not default to local-first.
	private func seedInitialBestURLFromSession() async {
		guard let cn = preferences.favoriteDeviceCN,
		      await remoteAccessService.hasValidTokens() else { return }

		let url: URL?
		if let saved = preferences.currentConnectedDevice,
		   saved.certificateCommonName == cn,
		   let key = saved.lastSuccessfulPathKey {
			if key.hasPrefix("mdns|") {
				let parts = key.split(separator: "|", omittingEmptySubsequences: false)
				if parts.count == 3, let port = Int(parts[2]) {
					url = URL(host: String(parts[1]), port: port)
				} else {
					url = nil
				}
			} else if let savedPath = saved.paths.first(where: { $0.pathKey == key }) {
				url = savedPath.asRemotePath().apiBaseURL()
			} else {
				url = nil
			}
		} else {
			url = Self.deviceBaseURLFromBookmark()
		}

		if let url {
			urlProvider.setBestURL(url, for: cn)
			Log.debug("[STX-RA]: Cold launch seeded base URL: \(url.absoluteString)")
		}
	}

	private static func deviceBaseURLFromBookmark() -> URL? {
		guard let bookmarkURL = OCBookmarkManager.shared.bookmarks.first?.url else { return nil }
		if bookmarkURL.lastPathComponent == "files" {
			return bookmarkURL.deletingLastPathComponent()
		}
		return bookmarkURL
	}

	/// Cold-launch bootstrap: seed URL then run path detection. Call from `HCContext.setup()`
	/// after reachability has delivered a real reading.
	public func performColdLaunchBootstrap() async {
		Self.logReachability("cold launch bootstrap starting")
		await seedInitialBestURLFromSession()
		await performLaunchPathDetection()
		Self.logReachability("cold launch bootstrap complete")
	}

	/// Clears stale local catalog entries when local paths are no longer available.
	public func handleNetworkPathSideEffects(_ state: NetworkState) async {
		guard !state.allowsLocalPaths else { return }
		let locals = await catalog.localDevices()
		guard !locals.isEmpty else { return }
		Self.logReachability("clearing \(locals.count) local device(s) — local paths disallowed")
		await catalog.clearLocalDevices()
		emit(.devicesUpdated(await catalog.mergedDevices()))
	}

	/// After seeding the last successful URL for a fast cold start, still run Algorithm B
	/// (priority path probing / local shortcut) so we can switch to a better link when available.
	private func performLaunchPathDetection() async {
		Self.logReachability("launch path detection starting")
		await connectivityCoordinator?.setPipelineReloading(true)
		defer { Task { await connectivityCoordinator?.setPipelineReloading(false) } }
		await coordinator.beginExternalDetection()
		let directResolved = await tryLaunchDirectPathResolution()
		if directResolved == false {
			Self.logReachability("direct path resolution failed — full reload")
			await pipeline.reloadDevices()
		} else {
			Self.logReachability("direct path resolution succeeded")
		}
		await coordinator.endExternalDetection()
		await reportCatalogSnapshot()
		await connectivityCoordinator?.noteLaunchDetectionComplete()
		Self.logReachability("launch path detection complete")
	}

	/// Algorithm B — same entry as `NetworkChangeCoordinator.performDetection`.
	private func tryLaunchDirectPathResolution() async -> Bool {
		guard let saved = preferences.currentConnectedDevice,
		      let seagateDeviceID = saved.seagateDeviceID,
		      !seagateDeviceID.isEmpty
		else {
			return false
		}

		// Algorithm B step 1 (local shortcut) does not require RA tokens. Steps 2+ do.
		if !allowsLocalPaths {
			guard await remoteAccessService.hasValidTokens() else { return false }
		}

		return await pipeline.attemptDirectResolution(
			seagateDeviceID: seagateDeviceID,
			certificateCommonName: saved.certificateCommonName,
			wifiAvailable: allowsLocalPaths
		)
	}

	private func installReloadTriggers() {
		networkChangeCancellable?.cancel()
		foregroundCancellable?.cancel()

		// Track foreground/background without UIApplication.shared (unavailable in extensions).
		// Spec: process any deferred network change when the app returns to foreground.
		foregroundCancellable = Publishers.Merge(
			NotificationCenter.default
				.publisher(for: UIApplication.didBecomeActiveNotification)
				.map { _ in true },
			NotificationCenter.default
				.publisher(for: UIApplication.willResignActiveNotification)
				.map { _ in false }
		)
		.sink { [coordinator] isActive in
			Task { await coordinator.handle(isActive ? .appBecameActive : .appResignedActive) }
		}

		// Spec Algorithm D: debounce rapid network changes for 3 seconds before re-detecting.
		networkChangeCancellable = reachability
			.updatesPublisher
			.debounce(for: .seconds(3), scheduler: DispatchQueue.main)
			.sink { [coordinator] state in
				Task { await coordinator.handle(.networkStateChanged(state)) }
			}
	}

	private func uninstallReloadTriggers() async {
		networkChangeCancellable?.cancel()
		networkChangeCancellable = nil
		foregroundCancellable?.cancel()
		foregroundCancellable = nil
		await coordinator.cancelCooldownTask()
	}

	// MARK: - Fast reprobe (no device reload)
	/// Reprobes paths for the logged-in active device only. No-op before login / device selection.
	public func reprobeExistingPaths() async {
		guard preferences.currentConnectedDevice != nil else { return }
		await pipeline.reprobeExistingPaths()
	}

	/// Convenience accessor for external callers (e.g. login flow) that don't need the
	/// merged view but want to know whether mDNS has produced anything yet.
	public func localDevices() async -> [LocalDevice] {
		await catalog.localDevices()
	}

	public nonisolated func start() {
		Task {
			await self.mdnsService.start()
			await self.reachability.start()
			await self.installReloadTriggers()
		}
	}

	public nonisolated func stop() {
		Task {
			await self.mdnsService.stop()
			await self.reachability.stop()
			await self.uninstallReloadTriggers()
		}
	}

	public func getMergedDevices(
		email: String,
		includeRemote: Bool = true,
		probeRemotePaths: Bool = true
	) async throws -> [MergedDevice] {
		try await pipeline.getMergedDevices(
			email: email,
			includeRemote: includeRemote,
			probeRemotePaths: probeRemotePaths
		)
	}

	// MARK: - Reload status
	public func isReloadingNow() async -> Bool {
		await pipeline.isReloadingNow()
	}

	private func handleMDNSUpdate(_ locals: [LocalDevice]) async {
		let catalogChanged = await pipeline.handleMDNSUpdate(locals)
		guard catalogChanged else {
			Self.logReachability("mDNS update (\(locals.count) local device(s)) — no catalog change, skipping recovery")
			return
		}
		Self.logReachability("mDNS update (\(locals.count) local device(s)) — triggering recovery")
		await connectivityCoordinator?.runPathRecovery(
			localPathsAllowed: allowsLocalPaths,
			skipInitialProbe: true
		)
	}

	private func handleStaticDeviceAddressChange(_ address: String?) async {
		Self.logReachability("static device address changed — triggering recovery")
		await pipeline.handleStaticDeviceAddressChange(address)
		await connectivityCoordinator?.runPathRecovery(
			localPathsAllowed: allowsLocalPaths,
			skipInitialProbe: true,
			localPathsFailed: !allowsLocalPaths
		)
	}

	// MARK: - Operation error handling → reprobe prompt
	/// Timeout, cannot connect, DNS — same as SDK @c isNetworkFailureError plus timedOut (status.php never hits core @c handleError).
	nonisolated private func isAutoReprobeTransportError(_ error: Error) -> Bool {
		let autoCodes: Set<Int> = [
			URLError.timedOut.rawValue,
			URLError.cannotConnectToHost.rawValue,
			URLError.cannotFindHost.rawValue,
			URLError.dnsLookupFailed.rawValue,
			URLError.networkConnectionLost.rawValue,
			URLError.notConnectedToInternet.rawValue
		]
		var current: Error? = error
		var depth = 0
		while let e = current, depth < 6 {
			let ns = e as NSError
			if ns.domain == NSURLErrorDomain, autoCodes.contains(ns.code) {
				return true
			}
			current = ns.userInfo[NSUnderlyingErrorKey] as? Error
			depth += 1
		}
		return false
	}

	public func forceReloadDevices() async {
		Self.logReachability("force reload starting")
		await connectivityCoordinator?.invalidateConfiguredProbePaths()
		await connectivityCoordinator?.noteCatalogReloadStarting()
		await coordinator.beginExternalDetection()
		await pipeline.reloadDevices()
		await coordinator.endExternalDetection()
		await connectivityCoordinator?.noteLoginBootstrapComplete()
		await reportCatalogSnapshot()
		Self.logReachability("force reload complete")
	}

	public func recalculateBestURLs() async {
		await pipeline.recalculateBestURLs()
	}

	// MARK: - Reset cached reachability state (e.g., on logout)
	public func resetState() async {
		Self.logReachability("reset state")
		await catalog.clear()
		await pathCacheStore.clear()
		await pipeline.cancelLoadTask()
		await coordinator.reset()
		emit(.devicesUpdated(await catalog.mergedDevices()))
		urlProvider.clearAll()
	}

	// MARK: - Forward operation errors → transport auto reprobe + availability signal
	public nonisolated func reportOperationError(_ error: Error) {
		guard isAutoReprobeTransportError(error) else { return }
		Task { await self.handleOperationError(error) }
	}

	private func handleOperationError(_ error: Error) async {
		Self.logReachability("transport error → path recovery (\(error.localizedDescription))")
		await connectivityCoordinator?.triggerPathRecoveryFromError(
			localPathsAllowed: allowsLocalPaths
		)
	}

	private func reportCatalogSnapshot() async {
		let cn = preferences.favoriteDeviceCN ?? preferences.currentConnectedDevice?.certificateCommonName
		let isReachable: Bool
		if let cn {
			isReachable = await reachableSelection(certificateCommonName: cn) != nil
			Self.logReachability(
				isReachable
					? "catalog snapshot→reachable (\(cn))"
					: "catalog snapshot→unreachable (\(cn))"
			)
		} else {
			isReachable = false
			Self.logReachability("catalog snapshot (no device CN)")
		}
		await connectivityCoordinator?.applyCatalogSnapshot(
			CatalogReachabilitySnapshot(
				hasDeviceCN: cn != nil,
				isReachable: isReachable
			)
		)
	}

	private static func logReachability(_ message: String) {
		Log.debug("[STX-CONN]: reachability \(message)")
	}

	/// Supplemental local paths for connectivity probes (mDNS / persisted local keys).
	public func supplementalProbePaths() async -> [RemoteDevice.Path] {
		guard allowsLocalPaths else { return [] }
		guard let cn = preferences.favoriteDeviceCN ?? preferences.currentConnectedDevice?.certificateCommonName else {
			return []
		}

		var paths: [RemoteDevice.Path] = []
		if let key = preferences.currentConnectedDevice?.lastSuccessfulPathKey,
		   let localPath = PathProber.localPath(fromMDNSPersistenceKey: key) {
			paths.append(localPath)
		}

		if let local = await catalog.localDevices().first(where: { $0.certificateCommonName == cn }) {
			let localPath = RemoteDevice.Path(kind: .local, address: local.host, port: local.port)
			if !paths.contains(where: { $0.key == localPath.key }) {
				paths.append(localPath)
			}
		}

		if let saved = preferences.currentConnectedDevice {
			for savedPath in saved.paths where savedPath.kind == .local {
				let localPath = savedPath.asRemotePath()
				if !paths.contains(where: { $0.key == localPath.key }) {
					paths.append(localPath)
				}
			}
		}

		return paths
	}

	public func isPreferredDeviceReachable() async -> Bool {
		guard let cn = preferences.favoriteDeviceCN ?? preferences.currentConnectedDevice?.certificateCommonName else {
			return false
		}
		return await reachableSelection(certificateCommonName: cn) != nil
	}

	private var allowsLocalPaths: Bool {
		reachability.currentState.allowsLocalPaths
	}

	// MARK: - Path selection
	//
	// Two predicates are exposed:
	// - `nextURLToAttempt(...)` → "what URL should the SDK try right now?".
	//   Returns a fallback even when no probe has succeeded yet, so the SDK always has
	//   *something* to retry against. Use for `OCBaseURLProvider` / RA-base-URL bridging.
	// - `reachableSelection(...)` → "do we have positive evidence that the device is
	//   reachable?". Returns `nil` unless an operational probe (or a validated mDNS
	//   local) actually exists. Use for connectivity-gate decisions: login readiness,
	//   "still failing after detection" auth-loss prompt, etc.
	//
	// Mixing the two was the cause of the connectivity-toast bug: the old single
	// `currentBestPath(...)` answered "what to attempt?" but was being read as
	// "is anything reachable?".

	public func nextURLToAttempt(certificateCommonName cn: String) async -> SelectedPath? {
		await catalog.nextURLToAttempt(
			forCN: cn,
			wifiAvailable: allowsLocalPaths,
			preferredPathKey: preferences.lastSuccessfulPathKey(forCN: cn)
		)
	}

	public func reachableSelection(certificateCommonName cn: String) async -> SelectedPath? {
		await catalog.reachableSelection(forCN: cn, wifiAvailable: allowsLocalPaths)
	}

	public func currentRemoteBaseURL() async -> URL? {
		guard let cn = preferences.favoriteDeviceCN else { return nil }
		return await catalog.remoteBaseURL(forCN: cn)
	}

	public func nextURLToAttempt(for merged: MergedDevice) -> SelectedPath? {
		let cn = merged.certificateCommonName
		let preferredKey = cn.flatMap { preferences.lastSuccessfulPathKey(forCN: $0) }
		return catalog.nextURLToAttempt(
			for: merged,
			wifiAvailable: allowsLocalPaths,
			preferredPathKey: preferredKey
		)
	}

	public func reachableSelection(for merged: MergedDevice) -> SelectedPath? {
		catalog.reachableSelection(for: merged, wifiAvailable: allowsLocalPaths)
	}

	/// Fast login path selection: probes only the selected device's links (Algorithm C).
	public func selectLoginPath(for merged: MergedDevice) async -> DetectionPipeline.LoginPathResult? {
		await pipeline.selectLoginPath(for: merged)
	}

}
