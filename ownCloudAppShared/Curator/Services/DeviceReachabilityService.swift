import Foundation

public final actor DeviceReachabilityService {
	public nonisolated static let shared = DeviceReachabilityService()

	public struct PathProbe: Sendable {
		public enum Source: Sendable {
			case remotePath(RemoteDevice.Path)
			case mdns(host: String, port: Int)
		}
		public let source: Source
		public let status: Status?
		public let about: About?
		public var isReachable: Bool { (status?.OOBE.done == true) && about != nil }
	}

	public struct MergedDevice: Sendable {
		public let remoteDevice: RemoteDevice?
		public let localDevice: LocalDevice?
		public let pathProbes: [PathProbe]
	}

	private var remoteDevices: [RemoteDevice] = []
	private var localDevices: [LocalDevice] = []
	private var remotePathProbesByCN: [String: [String: PathProbe]] = [:]
	private var onUpdate: (@MainActor ([MergedDevice]) -> Void)?

	private var raService: RemoteAccessService {
		RemoteAccessService.shared
	}

	private nonisolated var mdnsService: MDNSService {
		MDNSService.shared
	}

	private var loadTask: Task<[MergedDevice], Error>?

	private init() {
		mdnsService.onUpdate = { [weak self] locals in
			guard let self else { return }
			Task { await self.handleMDNSUpdate(locals) }
		}
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

	public nonisolated func start() { mdnsService.start() }
	public nonisolated func stop() { mdnsService.stop() }

	public func getMergedDevices(email: String) async throws -> [MergedDevice] {
		loadTask?.cancel()
		loadTask = Task.detached { [email] in
			let remote = (try? await RemoteAccessService.shared.getRemoteDevices(email: email)) ?? []
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

	private func currentMerged() -> [MergedDevice] {
		rebuildMerged(
			localDevices: localDevices,
			remoteDevices: remoteDevices,
			remotePathProbesByCN: remotePathProbesByCN
		)
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
			device.paths.compactMap { path in
				guard let url = makeAPIBaseURL(address: path.address, port: path.port) else { return nil }
				return (path, url, pathKey(for: path))
			}

		return await withTaskGroup(of: (String, PathProbe)?.self) { group in
			for item in items {
				group.addTask {
					let api = DeviceAPI(baseURL: item.url)

					var status: Status?
					var about: About?

					do { status = try await api.getStatus() } catch {
#if DEBUG
						Log.debug("[STX-RA]: Failed to get status. Error \(error)")
#endif
					}
					do { about  = try await api.getAbout()  } catch {
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
			for await pair in group {
				if let (k, v) = pair { map[k] = v }
			}
			return map
		}
	}

	nonisolated private func makeAPIBaseURL(address: String, port: Int?) -> URL? {
		var normalized = address
		if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
			normalized = "https://" + normalized
		}

		guard var components = URLComponents(string: normalized) else {
			return nil
		}
		if let port {
			components.port = port
		}
		guard let url = components.url else {
			return nil
		}
		return url.appendingPathComponent("api/v1/")
	}

	nonisolated private func pathKey(for path: RemoteDevice.Path) -> String {
		let kind: String = {
			switch path.kind {
				case .remote: return "remote"
				case .public: return "public"
				case .local: return "local"
			}
		}()
		return "\(kind)|\(path.address)|\(path.port ?? -1)"
	}

	private func orderPaths(_ paths: [RemoteDevice.Path]) -> [RemoteDevice.Path] {
		func priority(for kind: RemoteDevice.Path.Kind) -> Int {
			switch kind {
				case .local: return 0
				case .public: return 1
				case .remote: return 2
			}
		}
		return paths.sorted { a, b in
			let pa = priority(for: a.kind)
			let pb = priority(for: b.kind)
			if pa != pb { return pa < pb }
			let aa = "\(a.address):\(a.port ?? -1)"
			let bb = "\(b.address):\(b.port ?? -1)"
			return aa.localizedCaseInsensitiveCompare(bb) == .orderedAscending
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
			let orderedPaths = orderPaths(remote.paths)
			let probes: [PathProbe] = orderedPaths.compactMap { path in
				probesDict[pathKey(for: path)]
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

		return merged
	}
}
