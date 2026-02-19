import Foundation
import Network
import Combine
import ownCloudSDK
import UIKit

// Simple timeout error used by lightweight probe timeouts
private enum ReprobeTimeoutError: Error { case timedOut }

public final actor DeviceReachabilityService {
	public struct PathProbe: Sendable, Codable {
		public enum Source: Sendable, Codable {
			case remotePath(RemoteDevice.Path)
			case mdns(host: String, port: Int)
		}
		public let source: Source
		public let status: Status?
		public let about: About?
		public var isReachable: Bool {
			guard let status, let about else { return false }
			return status.state == .ready && status.OOBE.done && (about.certificate_common_name.isEmpty == false)
		}
	}

	// Lightweight timeout helper for async operations
	nonisolated private func withTimeout<T>(_ seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
		return try await withThrowingTaskGroup(of: T.self) { group in
			group.addTask {
				return try await operation()
			}
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
				throw ReprobeTimeoutError.timedOut
			}
			let value = try await group.next()!
			group.cancelAll()
			return value
		}
	}

	public struct MergedDevice: Sendable, Codable {
		public let remoteDevice: RemoteDevice?
		public let localDevice: LocalDevice?
		public let pathProbes: [PathProbe]

		public var certificateCommonName: String? {
			if let remoteDevice {
				return remoteDevice.certificateCommonName
			}
			if let localDevice {
				return localDevice.certificateCommonName
			}
			return nil
		}

		func asJSON() -> String? {
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			encoder.dateEncodingStrategy = .iso8601

			do {
				let data = try encoder.encode(self)
				if let json = String(data: data, encoding: .utf8) {
					return json
				}
				return nil
			} catch {
				return nil
			}
		}
	}

	public enum SelectedPath: Sendable {
		case remote(RemoteDevice.Path)
		case mdns(host: String, port: Int)

		public var url: URL? {
			switch self {
				case let .mdns(host, port):
					return URL(host: host, port: port)
				case let .remote(path):
					return URL(host: path.address, port: path.port)
			}
		}
	}

	public let urlProvider: DeviceReachabilityURLProvider

	private var remoteDevices: [RemoteDevice] = []
	public private(set) var localDevices: [LocalDevice] = []
	private var remotePathProbesByCN: [String: [String: PathProbe]] = [:]
    private var onUpdate: (@MainActor ([MergedDevice]) -> Void)?
    private var onReachabilityChange: (@MainActor (Bool) -> Void)?
	private var onEmailValidationRequest: (@MainActor (String) -> Void)?
	private var onReprobePrompt: (@MainActor (@escaping (Bool) -> Void) -> Void)?
	private var onRemoteBaseURLChange: (@MainActor (URL?) -> Void)?
	private var triggersCancellable: AnyCancellable?
	private var reachabilityStatusCancellable: AnyCancellable?
	private var staticDeviceAddressCancellable: AnyCancellable?
	private var loadTask: Task<[MergedDevice], Error>?
	private var isReloading: Bool = false
	private var lastNetworkState: NetworkState?
	private var staticRemoteDevice: RemoteDevice?

	private let reachability: ReachabilityObserving
	private let remoteAccessService: RemoteAccessService
	private let mdnsService: MDNSService
	private let preferences: HCPreferences

	public init(
		reachability: ReachabilityObserving,
		remoteAccessService: RemoteAccessService,
		mdnsService: MDNSService,
		preferences: HCPreferences
	) {
		self.reachability = reachability
		self.remoteAccessService = remoteAccessService
		self.mdnsService = mdnsService
		self.preferences = preferences

		urlProvider = DeviceReachabilityURLProvider(preferences: preferences)

		staticRemoteDevice = Self.buildStaticRemoteDevice(from: preferences.staticDeviceAddress)
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
		Task { await forceReloadDevices() }
	}

	private func installReloadTriggers() {
		// Cancel previous subscriptions
		triggersCancellable?.cancel()
		reachabilityStatusCancellable?.cancel()

		// Forward reachability availability to observers
		reachabilityStatusCancellable = reachability
			.updatesPublisher
			.sink { [weak self] state in
				guard let self else { return }
				Task {
					await self.handleNetworkChange(state)
					if let handler = await self.onReachabilityChange {
						await MainActor.run { handler(state.isReachable) }
					}
				}
			}

		// Merge triggers: reachability became reachable OR app became active OR periodic reevaluation
		let reachableTrigger = reachability
			.updatesPublisher
			.map { $0.isReachable }
			.removeDuplicates()
			.filter { $0 }
			.map { _ in () }
			.eraseToAnyPublisher()

		let appActiveTrigger = NotificationCenter.default
			.publisher(for: UIApplication.didBecomeActiveNotification)
			.map { _ in () }
			.eraseToAnyPublisher()

		let periodicTrigger = Timer
			.publish(every: 60, on: .main, in: .common)
			.autoconnect()
			.map { _ in () }
			.eraseToAnyPublisher()

		triggersCancellable = Publishers.MergeMany([reachableTrigger, appActiveTrigger, periodicTrigger])
			.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
			.sink { [weak self] in
				guard let self else { return }
				Task { await self.reprobeExistingPaths() }
			}
	}

	private func uninstallReloadTriggers() {
		triggersCancellable?.cancel()
		triggersCancellable = nil
		reachabilityStatusCancellable?.cancel()
		reachabilityStatusCancellable = nil
	}

	// MARK: - Fast reprobe (no device reload)
	public func reprobeExistingPaths() async {
		if isReloading { return }
		isReloading = true
		defer { isReloading = false }

		do {
			let probes = (try await self.probeAll(self.remoteDevices))
			self.setProbes(probes)
		} catch {
			Log.debug("[STX-RA]: Failed to probe device with error: \(error)")
		}
		let merged = self.currentMerged()
		if let onUpdate = self.onUpdate { await MainActor.run { onUpdate(merged) } }
		recalculateBestURLs()
	}

	private func handleMDNSUpdate(_ locals: [LocalDevice]) {
		self.localDevices = locals
		let merged = rebuildMerged(
			localDevices: localDevices,
			remoteDevices: remoteDevices,
			remotePathProbesByCN: remotePathProbesByCN,
			staticRemoteDevice: staticRemoteDevice
		)
		if let onUpdate { Task { @MainActor in onUpdate(merged) } }
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
		loadTask?.cancel()
		loadTask = Task.detached { [email, includeRemote, probeRemotePaths] in
			let remote: [RemoteDevice]
			if includeRemote {
				remote = try await self.remoteAccessService.getRemoteDevices(email: email)
			} else {
				remote = []
			}
			await self.setRemoteDevices(remote)
			if Task.isCancelled { return [] }

			let probes: [String: [String: PathProbe]]
			if includeRemote, probeRemotePaths, remote.isEmpty == false {
				probes = (try? await self.probeAll(remote)) ?? [:]
			} else {
				probes = [:]
			}
			await self.setProbes(probes)
			if Task.isCancelled { return [] }

			let merged = await self.currentMerged()
			if let onUpdate = await self.onUpdate {
				await MainActor.run { onUpdate(merged) }
			}
			return merged
		}
		return try await loadTask!.value
	}

	private func setRemoteDevices(_ v: [RemoteDevice]) {
		self.remoteDevices = v
	}

	private func setProbes(_ d: [String: [String: PathProbe]]) {
		self.remotePathProbesByCN = d
	}

	// MARK: - Reload status
	public func isReloadingNow() -> Bool {
		return isReloading
	}

    private func handleNetworkChange(_ state: NetworkState) async {
		if let last = lastNetworkState, last.interface == state.interface { return }
		lastNetworkState = state

		if let email = preferences.favoriteEmail {
			let hasToken = await remoteAccessService.hasValidTokens()
			if hasToken == false, let handler = onEmailValidationRequest {
				await MainActor.run { handler(email) }
			}
		}

		await forceReloadDevices()
    }

	private func reloadDevices() async {
		guard isReloading == false else {
			Log.debug("[STX-RA]: Reload requested but a reload is already in progress; skipping.")
			return
		}
		isReloading = true
		defer { isReloading = false }

		Log.debug("[STX-RA]: Reloading devices.")
		var didUpdateUsingEmail = false
		if let email = preferences.favoriteEmail {
			_ = (try? await getMergedDevices(email: email)) ?? []
			didUpdateUsingEmail = true // getMergedDevices() already fetches, probes and publishes
		}
		if remoteDevices.isEmpty, let saved = preferences.currentConnectedDevice {
			// Seed with saved connected device so we can probe paths after relaunch
			let paths: [RemoteDevice.Path] = saved.paths.map { p in
				let raKind: RADevicePathKind
				switch p.kind {
					case .local: raKind = .local
					case .public: raKind = .public
					case .remote: raKind = .remote
				}
				let ra = RADevicePath(type: raKind, address: p.address, port: p.port)
				return RemoteDevice.Path(raDevicePath: ra)
			}
			let seeded = RemoteDevice(
				seagateDeviceID: saved.seagateDeviceID ?? "",
				friendlyName: saved.friendlyName ?? "",
				hostname: saved.hostname ?? "",
				certificateCommonName: saved.certificateCommonName,
				paths: paths
			)
			self.setRemoteDevices([seeded])
			didUpdateUsingEmail = false // seeding requires a fresh probe below
		}
		// If we didn't perform getMergedDevices(), perform a probe + publish now (seeded or no email)
		if didUpdateUsingEmail == false {
			let probes = (try? await self.probeAll(self.remoteDevices)) ?? [:]
			self.setProbes(probes)
			let merged = self.currentMerged()
			if let onUpdate = self.onUpdate { await MainActor.run { onUpdate(merged) } }
			Log.debug("[STX-RA]: Remote count: \(remoteDevices.count). Local count: \(localDevices.count).")
		}
		recalculateBestURLs()
	}

	// MARK: - Operation error handling → reprobe prompt
	nonisolated private func shouldOfferReprobe(for error: Error) -> Bool {
		let ns = error as NSError
		if ns.domain == NSURLErrorDomain {
			let codes: [URLError.Code] = [
				.notConnectedToInternet,
				.networkConnectionLost,
				.cannotFindHost,
				.cannotConnectToHost,
				.dnsLookupFailed,
				.timedOut,
				.dataNotAllowed,
				.internationalRoamingOff,
				.callIsActive
			]
			return codes.contains(where: { $0.rawValue == ns.code })
		}
		return false
	}

	private func requestReprobeFromUI() async {
		guard let prompt = onReprobePrompt else {
			return
		}
		await MainActor.run {
			prompt { [weak self] accepted in
				guard let self else { return }
				if accepted {
					Task { await self.forceReloadDevices() }
				}
			}
		}
	}

	public func forceReloadDevices() async {
		await reloadDevices()
		await reprobeExistingPaths()
	}

	public func recalculateBestURLs() {
		for device in currentMerged() {
			guard
				let cn = device.certificateCommonName,
				let path = currentBestPath(for: device),
				let url = path.url
			else { continue }

			urlProvider.setBestURL(url, for: cn)
			Task {
				guard let cn = preferences.favoriteDeviceCN else {
					await onRemoteBaseURLChange?(nil)
					return
				}
				await onRemoteBaseURLChange?(remoteBaseURL(forCertificateCommonName: cn))
			}
		}
		Log.debug("[STX-RA]: Best RA URL: \(urlProvider.currentBaseURL()?.absoluteString ?? "")")
	}

	private func currentMerged() -> [MergedDevice] {
		rebuildMerged(
			localDevices: localDevices,
			remoteDevices: remoteDevices,
			remotePathProbesByCN: remotePathProbesByCN,
			staticRemoteDevice: staticRemoteDevice
		)
	}

	// MARK: - Observing merged updates (bridge support)
	public func observeMergedDevices(_ handler: @escaping @MainActor ([MergedDevice]) -> Void) {
		self.onUpdate = handler
		let snapshot = self.currentMerged()
		Task { @MainActor in handler(snapshot) }
	}

	// MARK: - Observing reachability updates (bridge support)
	public func observeReachability(_ handler: @escaping @MainActor (Bool) -> Void) {
		self.onReachabilityChange = handler
	}

	// MARK: - Observing email validation requests (when RA tokens are required)
	public func observeEmailValidationRequest(_ handler: @escaping @MainActor (String) -> Void) {
		self.onEmailValidationRequest = handler
	}

	// MARK: - Reset cached reachability state (e.g., on logout)
	public func resetState() async {
		remoteDevices = []
		localDevices = []
		remotePathProbesByCN = [:]
		loadTask?.cancel()
		loadTask = nil
		let merged = currentMerged()
		if let onUpdate = onUpdate {
			await MainActor.run { onUpdate(merged) }
		}
		urlProvider.clearAll()
	}

	public func observeRemoteBaseURL(_ handler: (@MainActor (URL?) -> Void)?) {
		self.onRemoteBaseURLChange = handler
	}

	// MARK: - Observing reprobe prompt requests (network errors from operations)
	public func observeReprobePrompt(_ handler: @escaping @MainActor (@escaping (Bool) -> Void) -> Void) {
		self.onReprobePrompt = handler
	}

	// MARK: - Forward operation errors to trigger a reprobe prompt
	public nonisolated func reportOperationError(_ error: Error) {
		guard shouldOfferReprobe(for: error) else { return }
		Task { await self.requestReprobeFromUI() }
	}

	// MARK: - Best path selection
	public func currentBestPath(certificateCommonName cn: String) -> SelectedPath? {
		// Prefer reachable remote path by priority
		if let remote = remoteDevices.first(where: { $0.certificateCommonName == cn }) {
			let probesDict = remotePathProbesByCN[cn] ?? [:]
			for path in remote.paths.ordered() {
				if let probe = probesDict[path.key], probe.isReachable {
					return .remote(path)
				}
			}
		}
		if let staticRemoteDevice, staticRemoteDevice.certificateCommonName == cn {
			let probesDict = remotePathProbesByCN[cn] ?? [:]
			for path in staticRemoteDevice.paths.ordered() {
				if let probe = probesDict[path.key], probe.isReachable {
					return .remote(path)
				}
			}
			if let first = staticRemoteDevice.paths.ordered().first {
				return .remote(first)
			}
		}

		// Fallback: local by CN
		if let local = localDevices.first(where: { $0.certificateCommonName == cn }) {
			return .mdns(host: local.host, port: local.port)
		}

		return nil
	}

	public func currentRemoteBaseURL() -> URL? {
		guard let cn = preferences.favoriteDeviceCN else { return nil }
		return remoteBaseURL(forCertificateCommonName: cn)
	}

	public func currentBestPath(for merged: MergedDevice) -> SelectedPath? {
		// 1) Prefer reachable probes in existing priority order (pathProbes already ordered and includes mDNS last if local exists)
		if let probe = merged.pathProbes.first(where: { $0.isReachable }) {
			switch probe.source {
				case .remotePath(let path):
					return .remote(path)
				case .mdns(let host, let port):
					return .mdns(host: host, port: port)
			}
		}

		// 2) Fallback: best ordered remote path
		if let remote = merged.remoteDevice, let first = remote.paths.ordered().first {
			return .remote(first)
		}

		// 3) Fallback: local mDNS if available
		if let local = merged.localDevice {
			return .mdns(host: local.host, port: local.port)
		}

		return nil
	}

	private func remoteBaseURL(forCertificateCommonName cn: String) -> URL? {
		guard let remote = remoteDevices.first(where: { $0.certificateCommonName == cn }) else {
			if let staticRemoteDevice, staticRemoteDevice.certificateCommonName == cn {
				if let remotePath = staticRemoteDevice.paths.ordered().first(where: { $0.kind == .remote }) {
					return remotePath.apiBaseURL()
				}
				return staticRemoteDevice.paths.ordered().first?.apiBaseURL()
			}
			return nil
		}

		let ordered = remote.paths.ordered()
		if let remotePath = ordered.first(where: { $0.kind == .remote }) {
			return remotePath.apiBaseURL()
		}

		return nil
	}

	private func probeAll(_ devices: [RemoteDevice]) async throws -> [String: [String: PathProbe]] {
		try await withThrowingTaskGroup(of: (String, [String: PathProbe]).self) { group in
			for device in devices {
				group.addTask {
					let pathMap = await self.probePaths(of: device)
					return (device.certificateCommonName, pathMap)
				}
			}
			var dict: [String: [String: PathProbe]] = [:]
			for try await (cn, map) in group { dict[cn] = map }
			return dict
		}
	}

	nonisolated private func probePaths(of device: RemoteDevice) async -> [String: PathProbe] {
		let items: [(path: RemoteDevice.Path, url: URL, key: String)] =
			device.paths.ordered().compactMap { path in
				guard let url = path.apiBaseURL() else { return nil }
				return (path, url, path.key)
			}

		return await withTaskGroup(of: (String, PathProbe)?.self) { group in
			for item in items {
				group.addTask {
					let api = DeviceAPI(deviceBaseURL: item.url)

					var status: Status?
					var about: About?

					do { status = try await self.withTimeout(5) { try await api.getStatus() } } catch {
#if DEBUG
						Log.debug("[STX-RA]: Failed to get status. URL: \(item.url). Error \(error)")
#endif
					}
					do { about  = try await self.withTimeout(5) { try await api.getAbout() } } catch {
#if DEBUG
						Log.debug("[STX-RA]: Failed to get about. URL: \(item.url). Error \(error)")
#endif
					}

					guard status != nil && about != nil else { return nil }

					let probe = PathProbe(
						source: .remotePath(item.path),
						status: status,
						about: about
					)
					return (item.key, probe)
				}
			}

			var map: [String: PathProbe] = [:]
			var foundReachable = false
			while let pair = await group.next() {
				if let (k, v) = pair {
					map[k] = v
					if v.isReachable && !foundReachable {
						foundReachable = true
					}
				}
			}
			return map
		}
	}

	private func appendMDNSProbeIfNeeded(_ probes: [PathProbe], local: LocalDevice) -> [PathProbe] {
		let about: About? = {
			guard let cn = local.certificateCommonName else { return nil }
			return About(hostname: local.host, certificate_common_name: cn, os_state: nil)
		}()
		let status = Status(state: .unknown, OOBE: .init(done: local.oobeIsDone), apps: nil)
		let mdnsProbe = PathProbe(source: .mdns(host: local.host, port: local.port), status: status, about: about)
		return probes + [mdnsProbe]
	}

	private func rebuildMerged(
		localDevices: [LocalDevice],
		remoteDevices: [RemoteDevice],
		remotePathProbesByCN: [String: [String: PathProbe]],
		staticRemoteDevice: RemoteDevice?
	) -> [MergedDevice] {
		var map: [String: MergedDevice] = [:]

		// Seed with remote devices
		for remote in remoteDevices {
			let probesDict = remotePathProbesByCN[remote.certificateCommonName] ?? [:]
			// Keep stable ordering: remote, public, local paths
			let orderedPaths = remote.paths.ordered()
			let probes: [PathProbe] = orderedPaths.compactMap { path in
				probesDict[path.key]
			}
			map[remote.certificateCommonName] = MergedDevice(
				remoteDevice: remote,
				localDevice: nil,
				pathProbes: probes
			)
		}

		// Merge local devices by certificate CN if available, otherwise by name
		for local in localDevices {
			if let certCN = local.certificateCommonName {
				if let existing = map[certCN] {
					map[certCN] = MergedDevice(
						remoteDevice: existing.remoteDevice,
						localDevice: local,
						pathProbes: appendMDNSProbeIfNeeded(existing.pathProbes, local: local)
					)
				} else {
					map[certCN] = MergedDevice(
						remoteDevice: nil,
						localDevice: local,
						pathProbes: appendMDNSProbeIfNeeded([], local: local)
					)
				}
			} else {
				// Fallback to name-based merge when CN is missing
				if let existing = map[local.name] {
					map[local.name] = MergedDevice(
						remoteDevice: existing.remoteDevice,
						localDevice: local,
						pathProbes: appendMDNSProbeIfNeeded(existing.pathProbes, local: local)
					)
				} else {
					map[local.name] = MergedDevice(
						remoteDevice: nil,
						localDevice: local,
						pathProbes: appendMDNSProbeIfNeeded([], local: local)
					)
				}
			}
		}

		var merged = Array(map.values).sorted { a, b in
			let nameA = a.remoteDevice?.friendlyName ?? a.localDevice?.name ?? ""
			let nameB = b.remoteDevice?.friendlyName ?? b.localDevice?.name ?? ""
			return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
		}

		if let staticRemoteDevice {
			let probesDict = remotePathProbesByCN[staticRemoteDevice.certificateCommonName] ?? [:]
			let staticProbes = staticRemoteDevice.paths.compactMap { probesDict[$0.key] }
			let staticMerged = MergedDevice(
				remoteDevice: staticRemoteDevice,
				localDevice: nil,
				pathProbes: staticProbes
			)
			merged.insert(staticMerged, at: 0)
		}

		Log.debug("[STX-RA]: Merged: ")
		merged.forEach { Log.debug($0.asJSON() ?? "") }
		return merged
	}

	private func handleStaticDeviceAddressChange(_ address: String?) async {
		staticRemoteDevice = Self.buildStaticRemoteDevice(from: address)
		let merged = currentMerged()
		if let onUpdate { await MainActor.run { onUpdate(merged) } }
		recalculateBestURLs()
	}

	private static func buildStaticRemoteDevice(from address: String?) -> RemoteDevice? {
		guard let address, address.isEmpty == false else { return nil }
		guard let components = URLComponents(string: address) else { return nil }
		guard let host = components.host, host.isEmpty == false else { return nil }
		let path = RemoteDevice.Path(kind: .remote, address: address, port: nil)
		return RemoteDevice(
			seagateDeviceID: address,
			friendlyName: address,
			hostname: host,
			certificateCommonName: address,
			paths: [path]
		)
	}
}

// MARK: - URL Provider Bridge (OCBaseURLProvider)
@objcMembers
public final class DeviceReachabilityURLProvider: NSObject, OCBaseURLProvider {
	private let cacheQueue = DispatchQueue(label: "com.personalCloudFiles.best-url-cache", attributes: .concurrent)
	private var bestURLByCN: [String: URL] = [:]

	private let preferences: HCPreferences

	init(preferences: HCPreferences) {
		self.preferences = preferences
	}

	public func setBestURL(_ url: URL, for cn: String) {
		var previous: URL?
		cacheQueue.sync { previous = self.bestURLByCN[cn] }

		let changed: Bool = {
			guard let prev = previous else { return true }
			return (prev.scheme?.lowercased() != url.scheme?.lowercased())
				|| (prev.host?.lowercased() != url.host?.lowercased())
				|| (prev.port != url.port)
		}()

		// If host/port/scheme didn’t change, do nothing
		guard changed else { return }

		cacheQueue.async(flags: .barrier) { self.bestURLByCN[cn] = url }

		DispatchQueue.main.async {
			let bookmarks = OCBookmarkManager.shared.bookmarks
			let favCN = self.preferences.favoriteDeviceCN
			for bookmark in bookmarks {
				var shouldUpdate = false
				if let bmURL = bookmark.url {
					if let prev = previous {
						// Bookmark points to previous host/port → update to new best
						let prevHost = prev.host?.lowercased()
						let bmHost = bmURL.host?.lowercased()
						let sameHost = (prevHost?.isEmpty == false) && (prevHost == bmHost)
						let prevPort = prev.port
						let bmPort = bmURL.port
						let portsEqual = (prevPort != nil) ? (prevPort == bmPort) : (bmPort == nil)
						shouldUpdate = sameHost && portsEqual
					} else if favCN == cn {
						// First time setting best URL for favorite device (e.g. after auto-login) → update bookmark
						shouldUpdate = true
					}
				}
				if shouldUpdate, let bmURL = bookmark.url {
					var comps = URLComponents(url: bmURL, resolvingAgainstBaseURL: false)
					let newComps = URLComponents(url: url, resolvingAgainstBaseURL: false)
					if let newScheme = newComps?.scheme, !newScheme.isEmpty { comps?.scheme = newScheme }
					if let newHost = newComps?.host, !newHost.isEmpty { comps?.host = newHost }
					comps?.port = newComps?.port
					if let adjusted = comps?.url {
						bookmark.url = adjusted
						OCBookmarkManager.shared.updateBookmark(bookmark)
					}
				}

				OCCoreManager.shared.requestCore(for: bookmark, setup: nil) { core, _ in
					guard let core else { return }
					// Only cancel existing traffic if we are switching away from a known base
					if previous != nil {
						core.connection.cancelAllRequestsForCurrentPartition()
					}
					core.connection.validateConnection(withReason: "Best URL switched", dueToResponseTo: nil)
				}
			}
		}
	}

	@objc(currentBaseURL)
	public func currentBaseURL() -> URL? {
		if let cn = preferences.favoriteDeviceCN,
		   let url = cachedBestURL(for: cn) {
			Log.debug("[STX-RA]: Returned best URL: \(url)")
			return url
		}
		return nil
	}

	public func clearAll() {
		cacheQueue.async(flags: .barrier) { self.bestURLByCN.removeAll() }
	}

	private func cachedBestURL(for cn: String) -> URL? {
		var url: URL?
		cacheQueue.sync { url = bestURLByCN[cn] }
		return url
	}
}
