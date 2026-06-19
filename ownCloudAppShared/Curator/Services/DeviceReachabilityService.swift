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
			emit: { event in subject.send(event) }
		)
		self.pipeline = pipeline
		self.coordinator = NetworkChangeCoordinator(
			pipeline: pipeline,
			remoteAccessService: remoteAccessService,
			preferences: preferences,
			emit: { event in subject.send(event) },
			onPathRecoveryNeeded: { [connectivityCoordinator] in
				await connectivityCoordinator?.evaluate(reason: .discovery)
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
		guard let cn = preferences.favoriteDeviceCN else { return }

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

		guard let url else { return }
		// WAN paths require RA tokens; mDNS-only sessions can seed immediately on the LAN.
		let isMDNSPath = preferences.currentConnectedDevice?.lastSuccessfulPathKey?.hasPrefix("mdns|") == true
		if !isMDNSPath {
			guard await remoteAccessService.hasValidTokens() else { return }
		} else {
			guard allowsLocalPaths else { return }
		}

		urlProvider.setBestURL(url, for: cn)
		Log.debug("[STX-RA]: Cold launch seeded base URL: \(url.absoluteString)")
	}

	private static func deviceBaseURLFromBookmark() -> URL? {
		guard let bookmarkURL = OCBookmarkManager.shared.bookmarks.first?.url else { return nil }
		if bookmarkURL.lastPathComponent == "files" {
			return bookmarkURL.deletingLastPathComponent()
		}
		return bookmarkURL
	}

	/// Cold launch: seed URL then run path detection. Call from `HCContext.setup()`
	/// after reachability has delivered a real reading.
	public func performColdLaunchPathDetection() async {
		Self.logReachability("cold launch path detection starting")
		await seedInitialBestURLFromSession()
		await performLaunchPathDetection()
		await connectivityCoordinator?.evaluate(reason: .discovery)
		Self.logReachability("cold launch path detection complete")
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
		await coordinator.beginExternalDetection()
		let directResolved = await tryLaunchDirectPathResolution()
		if directResolved == false {
			Self.logReachability("direct path resolution failed — full reload")
			await pipeline.reloadDevices()
		} else {
			Self.logReachability("direct path resolution succeeded")
		}
		await coordinator.endExternalDetection()
		Self.logReachability("launch path detection complete")
	}

	/// Algorithm B — same entry as `NetworkChangeCoordinator.performDetection`.
	private func tryLaunchDirectPathResolution() async -> Bool {
		guard let saved = preferences.currentConnectedDevice,
		      !saved.certificateCommonName.isEmpty
		else { return false }
		let cn = saved.certificateCommonName

		if allowsLocalPaths,
		   (saved.seagateDeviceID ?? "").isEmpty,
		   await pipeline.attemptMDNSOnlyDirectResolution(
		   	certificateCommonName: cn,
		   	preferredPathKey: saved.lastSuccessfulPathKey
		   ) {
			return true
		}

		guard let seagateDeviceID = saved.seagateDeviceID, !seagateDeviceID.isEmpty else {
			return false
		}

		// Algorithm B step 1 (local shortcut) does not require RA tokens. Steps 2+ do.
		if !allowsLocalPaths {
			guard await remoteAccessService.hasValidTokens() else { return false }
		}

		return await pipeline.attemptDirectResolution(
			seagateDeviceID: seagateDeviceID,
			certificateCommonName: cn,
			wifiAvailable: allowsLocalPaths
		)
	}

	private func installReloadTriggers() {
		// Reachability and app-foreground are observed once, by `ConnectivityStateCoordinator`,
		// which funnels them into `evaluate(reason:)`. The discovery engine no longer subscribes
		// to those signals itself — it only reloads the catalog when `evaluate` asks it to.
		networkChangeCancellable?.cancel()
		networkChangeCancellable = nil
		foregroundCancellable?.cancel()
		foregroundCancellable = nil
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
		Self.logReachability("mDNS update (\(locals.count) local device(s)) — triggering evaluate")
		await connectivityCoordinator?.evaluate(reason: .discovery)
	}

	private func handleStaticDeviceAddressChange(_ address: String?) async {
		Self.logReachability("static device address changed — triggering evaluate")
		await pipeline.handleStaticDeviceAddressChange(address)
		await connectivityCoordinator?.evaluate(reason: .discovery)
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

	// MARK: - Post-login catalog sync

	/// Refreshes the RA device list without clearing login probes or restarting mDNS.
	public func mergeRemoteCatalogAfterLogin() async {
		guard let email = preferences.favoriteEmail, !email.isEmpty else { return }
		guard await remoteAccessService.hasValidTokens() else { return }
		do {
			try await pipeline.mergeRemoteDevices(email: email)
			await connectivityCoordinator?.invalidateConfiguredProbePaths()
			Self.logReachability("post-login remote catalog merged")
		} catch {
			Self.logReachability("post-login remote catalog merge failed: \(error.localizedDescription)")
		}
	}

	/// Discovery step invoked by `ConnectivityStateCoordinator.evaluate` when no known path
	/// responded. Refreshes the catalog (mDNS / RA) and recalculates the best URL. It does NOT
	/// drive the banner — the evaluator inspects the freshly-probed catalog afterwards.
	public func forceReloadDevices() async {
		Self.logReachability("force reload starting")
		await connectivityCoordinator?.invalidateConfiguredProbePaths()
		if await tryMDNSOnlyReloadIfApplicable() {
			Self.logReachability("mDNS-only reload succeeded — skipping full catalog reset")
		} else {
			await coordinator.beginExternalDetection()
			await pipeline.reloadDevices()
			await coordinator.endExternalDetection()
		}
		Self.logReachability("force reload complete")
	}

	/// Lightweight reload for mDNS-only sessions: re-validates the persisted local path
	/// without clearing the catalog or restarting mDNS discovery.
	private func tryMDNSOnlyReloadIfApplicable() async -> Bool {
		guard allowsLocalPaths,
		      let saved = preferences.currentConnectedDevice,
		      (saved.seagateDeviceID ?? "").isEmpty,
		      saved.paths.isEmpty,
		      !saved.certificateCommonName.isEmpty
		else { return false }
		let cn = saved.certificateCommonName
		return await pipeline.attemptMDNSOnlyDirectResolution(
			certificateCommonName: cn,
			preferredPathKey: saved.lastSuccessfulPathKey
		)
	}

	public func recalculateBestURLs() async {
		await pipeline.recalculateBestURLs()
	}

	/// Applies a path that `PathProber` already verified reachable: switches the SDK base URL
	/// immediately and persists it as the preferred path, avoiding a full catalog reload when
	/// the evaluator just needs to switch links (e.g. to a higher-priority local path).
	public func applyBestProbedPath(_ path: RemoteDevice.Path) async {
		guard let cn = preferences.favoriteDeviceCN ?? preferences.currentConnectedDevice?.certificateCommonName,
		      let url = path.apiBaseURL()
		else { return }
		// Local paths are persisted in the `mdns|host|port` form the cold-launch seeding expects.
		let key = path.kind == .local ? "mdns|\(path.address)|\(path.port ?? -1)" : path.key
		urlProvider.setBestURL(url, for: cn)
		preferences.updateLastSuccessfulPathKey(key, forCN: cn)
		Self.logReachability("applied probed best path \(key)")
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
		Self.logReachability("transport error → evaluate (\(error.localizedDescription))")
		await connectivityCoordinator?.triggerPathRecoveryFromError()
	}

	private static func logReachability(_ message: String) {
		Log.debug("[STX-CONN]: reachability \(message)")
	}

	/// Every path that should be considered during connectivity probes for the preferred device.
	public func allProbePaths() async -> [RemoteDevice.Path] {
		guard let cn = preferences.favoriteDeviceCN ?? preferences.currentConnectedDevice?.certificateCommonName else {
			return []
		}

		var paths: [RemoteDevice.Path] = []
		var seen = Set<String>()
		func append(_ path: RemoteDevice.Path) {
			guard seen.insert(path.key).inserted else { return }
			paths.append(path)
		}

		let merged = await catalog.mergedDevices().first(where: { $0.certificateCommonName == cn })
		if let remote = merged?.remoteDevice {
			for path in remote.paths.ordered() {
				append(path)
			}
		}

		if let staticRemote = await catalog.staticRemoteDevice(),
		   staticRemote.certificateCommonName == cn {
			for path in staticRemote.paths.ordered() {
				append(path)
			}
		}

		if let remote = await catalog.remoteDevice(forCN: cn) {
			for path in remote.paths.ordered() {
				append(path)
			}
		}

		if let saved = preferences.currentConnectedDevice {
			for savedPath in saved.paths {
				append(savedPath.asRemotePath())
			}
		}

		if allowsLocalPaths {
			if let local = merged?.localDevice {
				append(RemoteDevice.Path(kind: .local, address: local.host, port: local.port))
			}
			for local in await catalog.localDevices() where local.certificateCommonName == cn {
				append(RemoteDevice.Path(kind: .local, address: local.host, port: local.port))
			}
			if let key = preferences.currentConnectedDevice?.lastSuccessfulPathKey,
			   let localPath = PathProber.localPath(fromMDNSPersistenceKey: key) {
				append(localPath)
			}
		}

		return paths.ordered()
	}

	private func hasNonLocalPathToAttempt(certificateCommonName cn: String) async -> Bool {
		guard let next = await nextURLToAttempt(certificateCommonName: cn) else { return false }
		switch next {
			case .mdns:
				return false
			case .remote(let path):
				return path.kind != .local
		}
	}

	public func hasNonLocalPathToAttemptForFavoriteDevice() async -> Bool {
		guard let cn = preferences.favoriteDeviceCN ?? preferences.currentConnectedDevice?.certificateCommonName else {
			return false
		}
		return await hasNonLocalPathToAttempt(certificateCommonName: cn)
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
