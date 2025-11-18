import Foundation
import Network
import Combine
import ownCloudSDK
import UIKit

// Simple timeout error used by lightweight probe timeouts
private enum ReprobeTimeoutError: Error { case timedOut }

public final actor DeviceReachabilityService {
	public struct PathProbe: Sendable {
		public enum Source: Sendable {
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

	public struct MergedDevice: Sendable {
		public let remoteDevice: RemoteDevice?
		public let localDevice: LocalDevice?
		public let pathProbes: [PathProbe]

		var certificateCommonName: String? {
			if let remoteDevice {
				return remoteDevice.certificateCommonName
			}
			if let localDevice {
				return localDevice.certificateCommonName
			}
			return nil
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
	private var localDevices: [LocalDevice] = []
	private var remotePathProbesByCN: [String: [String: PathProbe]] = [:]
    private var onUpdate: (@MainActor ([MergedDevice]) -> Void)?
    private var onReachabilityChange: (@MainActor (Bool) -> Void)?
	private var triggersCancellable: AnyCancellable?
	private var reachabilityStatusCancellable: AnyCancellable?
	private var loadTask: Task<[MergedDevice], Error>?
	private var isReloading: Bool = false

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

		mdnsService.onUpdate = { [weak self] locals in
			guard let self else { return }
			Task { await self.handleMDNSUpdate(locals) }
		}
		Task { await reloadDevices() }
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

		let probes = (try? await self.probeAll(self.remoteDevices)) ?? [:]
		self.setProbes(probes)
		let merged = self.currentMerged()
		if let onUpdate = self.onUpdate { await MainActor.run { onUpdate(merged) } }
		recalculateBestURLs()
	}

	private func handleMDNSUpdate(_ locals: [LocalDevice]) {
		self.localDevices = locals
		let merged = rebuildMerged(
			localDevices: localDevices,
			remoteDevices: remoteDevices,
			remotePathProbesByCN: remotePathProbesByCN
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

	public func getMergedDevices(email: String) async throws -> [MergedDevice] {
		loadTask?.cancel()
		loadTask = Task.detached { [email] in
			let remote = (try? await self.remoteAccessService.getRemoteDevices(email: email)) ?? []
			await self.setRemoteDevices(remote)
			if Task.isCancelled { return [] }

			let probes = (try? await self.probeAll(remote)) ?? [:]
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
		guard state.isReachable else { return }
		await reloadDevices()
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
		if let email = preferences.currentEmail {
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

	private func recalculateBestURLs() {
		for device in currentMerged() {
			guard
				let cn = device.certificateCommonName,
				let path = currentBestPath(certificateCommonName: cn),
				let url = path.url
			else { continue }

			urlProvider.setBestURL(url, for: cn)
		}
		Log.debug("[STX-RA]: Best RA URL: \(urlProvider.currentBaseURL()?.absoluteString ?? "")")
	}

	private func currentMerged() -> [MergedDevice] {
		rebuildMerged(
			localDevices: localDevices,
			remoteDevices: remoteDevices,
			remotePathProbesByCN: remotePathProbesByCN
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
			// Fallback: first ordered path
			if let first = remote.paths.ordered().first { return .remote(first) }
		}

		// Fallback: local by CN
		if let local = localDevices.first(where: { $0.certificateCommonName == cn }) {
			return .mdns(host: local.host, port: local.port)
		}

		return nil
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
					let api = DeviceAPI(baseURL: item.url)

					var status: Status?
					var about: About?

					do { status = try await self.withTimeout(0.8) { try await api.getStatus() } } catch {
#if DEBUG
						Log.debug("[STX-RA]: Failed to get status. Error \(error)")
#endif
					}
					do { about  = try await self.withTimeout(0.8) { try await api.getAbout() } } catch {
#if DEBUG
						Log.debug("[STX-RA]: Failed to get about. Error \(error)")
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
						group.cancelAll() // Short-circuit: we have a reachable path; stop probing slower ones
					}
				}
			}
			return map
		}
	}

	private func appendMDNSProbeIfNeeded(_ probes: [PathProbe], local: LocalDevice) -> [PathProbe] {
		let about: About? = {
			guard let cn = local.certificateCommonName else { return nil }
			return About(hostname: local.host, certificate_common_name: cn)
		}()
		let status = Status(state: .unknown, OOBE: .init(done: local.oobeIsDone))
		let mdnsProbe = PathProbe(source: .mdns(host: local.host, port: local.port), status: status, about: about)
		return probes + [mdnsProbe]
	}

	private func rebuildMerged(
		localDevices: [LocalDevice],
		remoteDevices: [RemoteDevice],
		remotePathProbesByCN: [String: [String: PathProbe]]
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

		let merged = Array(map.values).sorted { a, b in
			let nameA = a.remoteDevice?.friendlyName ?? a.localDevice?.name ?? ""
			let nameB = b.remoteDevice?.friendlyName ?? b.localDevice?.name ?? ""
			return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
		}

		Log.debug("[STX-RA]: Merged: \(merged)")
		return merged
	}
}

// MARK: - URL Provider Bridge (OCBaseURLProvider)
@objcMembers
public final class DeviceReachabilityURLProvider: NSObject, OCBaseURLProvider {
	private let cacheQueue = DispatchQueue(label: "com.curator.best-url-cache", attributes: .concurrent)
	private var bestURLByCN: [String: URL] = [:]

	private let preferences: HCPreferences

	init(preferences: HCPreferences) {
		self.preferences = preferences
	}

	public func setBestURL(_ url: URL, for cn: String) {
		cacheQueue.async(flags: .barrier) {
			self.bestURLByCN[cn] = url
		}

		DispatchQueue.main.async {
			let bookmarks = OCBookmarkManager.shared.bookmarks
			for bookmark in bookmarks {
				OCCoreManager.shared.requestCore(for: bookmark, setup: nil) { core, _ in
					guard let core else { return }
					core.connection.validateConnection(withReason: "Best URL switched", dueToResponseTo: nil)
				}
			}
		}
	}

	@objc(currentBaseURL)
	public func currentBaseURL() -> URL? {
		if let cn = preferences.currentCertificateCN,
		   let url = cachedBestURL(for: cn) {
			return url
		}
		return nil
	}

	private func cachedBestURL(for cn: String) -> URL? {
		var url: URL?
		cacheQueue.sync { url = bestURLByCN[cn] }
		return url
	}
}
