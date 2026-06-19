import Foundation
import ownCloudSDK

/// Path recovery orchestration extracted from `ConnectivityStateCoordinator`.
final class ConnectivityRecoveryRunner {
	struct Dependencies {
		let pathProber: PathProber
		var preferences: HCPreferences?
		var remoteAccessService: RemoteAccessService?
		var supplementalProbePaths: (() async -> [RemoteDevice.Path])?
		var isPreferredDeviceReachable: (() async -> Bool)?
		var pathRecoveryHandler: (() async throws -> Void)?
		var configuredProbePaths: ((HCPreferences) async -> [RemoteDevice.Path])?
		var requestRAAuthentication: ((String) async -> Bool)?
		var recoveryEmail: () -> String?
		var setConnectingForAlternateProbe: () async -> Void
		var applyDeviceAccess: @Sendable (DeviceAccessState, ConnectivityAccessPolicy) async -> Void
		var currentDeviceAccess: @Sendable () async -> DeviceAccessState
		var beginRemoteAuthentication: @Sendable () async -> Void
		var endRemoteAuthentication: @Sendable (DeviceAccessState) async -> Void
		var log: (String) -> Void
	}

	private(set) var task: Task<Void, Never>?
	private(set) var pendingRequest: ConnectivityRecoveryRequest?

	var isInFlight: Bool { task != nil }

	func reset() {
		task?.cancel()
		task = nil
		pendingRequest = nil
	}

	func run(
		request incoming: ConnectivityRecoveryRequest,
		session: ConnectivitySessionState,
		snackbarDrivingEnabled: Bool,
		dependencies: Dependencies,
		perform: @escaping @Sendable (ConnectivityRecoveryRequest, Dependencies, ConnectivitySessionState, Bool) async -> Void
	) async {
		if let inFlight = task {
			pendingRequest = ConnectivityRecoveryRequest.merge(pendingRequest, with: incoming)
			dependencies.log("recovery coalesced with in-flight task")
			await inFlight.value
			return
		}

		var request = incoming
		repeat {
			dependencies.log(
				"recovery started (skipProbe=\(request.skipInitialProbe) "
					+ "localFailed=\(request.localPathsFailed) device=\(session.deviceAccess))"
			)
			task = Task {
				await perform(request, dependencies, session, snackbarDrivingEnabled)
			}
			await task?.value
			task = nil

			guard let pending = pendingRequest else { break }
			pendingRequest = nil
			request = pending
		} while true
	}

	static func performRecovery(
		_ request: ConnectivityRecoveryRequest,
		dependencies: Dependencies,
		session: ConnectivitySessionState,
		snackbarDrivingEnabled: Bool
	) async {
		switch session.checkRecoveryEligibility() {
			case .eligible:
				break
			case .ineligible:
				return
		}
		if Task.isCancelled { return }

		if snackbarDrivingEnabled,
		   await shouldShowConnectingAtRecoveryStart(request: request, dependencies: dependencies) {
			await dependencies.applyDeviceAccess(.connecting, .normal)
		}

		var localProbeFailed = request.localPathsFailed
		if localProbeFailed, await preferredDeviceIsReachable(dependencies) {
			localProbeFailed = false
		}

		if await tryInitialProbeRecovery(
			request: request,
			localProbeFailed: &localProbeFailed,
			dependencies: dependencies
		) {
			return
		}

		if await tryFullCatalogReload(request: request, dependencies: dependencies) {
			return
		}

		if request.localPathsAllowed {
			localProbeFailed = true
		}

		if await tryRemoteAuthentication(
			request: request,
			localProbeFailed: localProbeFailed,
			dependencies: dependencies
		) {
			return
		}

		dependencies.log("recovery finalize (no RA required)")
		await finalizeDeviceAccessAfterRecovery(dependencies: dependencies)
	}

	// MARK: - Recovery steps

	private static func tryInitialProbeRecovery(
		request: ConnectivityRecoveryRequest,
		localProbeFailed: inout Bool,
		dependencies: Dependencies
	) async -> Bool {
		guard !request.skipInitialProbe, let preferences = dependencies.preferences else { return false }

		let paths = await configuredProbePaths(preferences: preferences, dependencies: dependencies)
		guard !paths.isEmpty else { return false }

		let result = await probeConfiguredPaths(
			paths: paths,
			currentPathKey: preferences.currentConnectedDevice?.lastSuccessfulPathKey,
			localPathsAllowed: request.localPathsAllowed,
			dependencies: dependencies
		)
		if Task.isCancelled { return true }

		switch result {
			case .currentPathReachable:
				dependencies.log("recovery initial probe→current path reachable")
				await dependencies.applyDeviceAccess(.connected, .pathEvidence)
				return true
			case .alternatePathReachable:
				dependencies.log("recovery initial probe→alternate reachable — reloading paths")
				await invokePathRecoveryHandler(dependencies: dependencies)
				await dependencies.applyDeviceAccess(.connected, .pathEvidence)
				return true
			case .allUnreachable:
				dependencies.log("recovery initial probe→all unreachable")
				localProbeFailed = true
				return false
		}
	}

	private static func tryFullCatalogReload(
		request: ConnectivityRecoveryRequest,
		dependencies: Dependencies
	) async -> Bool {
		if !request.localPathsFailed,
		   !request.alternatePathReachable,
		   await preferredDeviceIsReachable(dependencies),
		   await dependencies.currentDeviceAccess() == .connected {
			dependencies.log("recovery→reload skipped (already connected and reachable)")
			return true
		}
		dependencies.log("recovery→full path reload")
		await invokePathRecoveryHandler(dependencies: dependencies)
		if Task.isCancelled { return true }
		guard await preferredDeviceIsReachable(dependencies) else {
			await applyDisconnectedAfterUnreachableReload(dependencies: dependencies, context: "reload")
			return false
		}
		dependencies.log("recovery→connected after reload (catalog reachable)")
		await dependencies.applyDeviceAccess(.connected, .pathEvidence)
		return true
	}

	private static func tryRemoteAuthentication(
		request: ConnectivityRecoveryRequest,
		localProbeFailed: Bool,
		dependencies: Dependencies
	) async -> Bool {
		guard await requiresRAAuthentication(
			localPathsAllowed: request.localPathsAllowed,
			localProbeFailed: localProbeFailed,
			dependencies: dependencies
		) else {
			return false
		}

		dependencies.log("recovery requires RA authentication")
		guard let email = dependencies.recoveryEmail() else {
			Log.debug("[STX-RA]: RA tokens missing but no email available for verification.")
			await dependencies.applyDeviceAccess(.disconnected, .duringRAAuth)
			return true
		}
		Log.debug("[STX-RA]: Requesting RA verification for \(email).")
		await dependencies.beginRemoteAuthentication()
		await dependencies.applyDeviceAccess(.connecting, .duringRAAuth)
		let authenticated = await dependencies.requestRAAuthentication?(email) ?? false
		if Task.isCancelled {
			await dependencies.endRemoteAuthentication(.connecting)
			return true
		}
		if !authenticated {
			dependencies.log("recovery RA auth failed")
			await dependencies.endRemoteAuthentication(.disconnected)
			await dependencies.applyDeviceAccess(.disconnected, .duringRAAuth)
			return true
		}
		await dependencies.endRemoteAuthentication(.connecting)
		dependencies.log("recovery RA auth succeeded — reloading paths")
		await invokePathRecoveryHandler(dependencies: dependencies)
		await finalizeDeviceAccessAfterRecovery(dependencies: dependencies)
		return true
	}

	private static func finalizeDeviceAccessAfterRecovery(dependencies: Dependencies) async {
		let current = await dependencies.currentDeviceAccess()
		if await preferredDeviceIsReachable(dependencies) {
			guard current == .connecting else { return }
			dependencies.log("recovery finalize→connected (catalog reachable)")
			await dependencies.applyDeviceAccess(.connected, .recoveryFinalize)
			return
		}
		await applyDisconnectedAfterUnreachableReload(dependencies: dependencies, context: "finalize")
	}

	private static func applyDisconnectedAfterUnreachableReload(
		dependencies: Dependencies,
		context: String
	) async {
		let current = await dependencies.currentDeviceAccess()
		guard current == .connecting || current == .connected else {
			dependencies.log("recovery \(context) skipped (device=\(current))")
			return
		}
		dependencies.log("recovery \(context)→disconnected (catalog unreachable)")
		await dependencies.applyDeviceAccess(.disconnected, .recoveryFinalize)
	}

	// MARK: - Probe helpers

	static func configuredProbePaths(
		preferences: HCPreferences,
		dependencies: Dependencies
	) async -> [RemoteDevice.Path] {
		if let resolver = dependencies.configuredProbePaths {
			return await resolver(preferences)
		}
		var paths = pathsForConnectedDevice(preferences: preferences)
		if let supplemental = await dependencies.supplementalProbePaths?() {
			paths = merging(paths, with: supplemental)
		}
		return paths
	}

	private static func invokePathRecoveryHandler(dependencies: Dependencies) async {
		guard let handler = dependencies.pathRecoveryHandler else { return }
		do {
			try await handler()
		} catch {
			ConnectivityEventLog.recoveryFailure("catalog reload", error: error)
		}
	}

	static func probeConfiguredPaths(
		paths: [RemoteDevice.Path],
		currentPathKey: String?,
		localPathsAllowed: Bool,
		dependencies: Dependencies
	) async -> PathConnectivityProbeResult {
		await dependencies.pathProber.probeConnectivityCurrentFirst(
			paths: paths,
			currentPathKey: currentPathKey,
			localPathsAllowed: localPathsAllowed
		) {
			await dependencies.setConnectingForAlternateProbe()
		}
	}

	private static func preferredDeviceIsReachable(_ dependencies: Dependencies) async -> Bool {
		await (dependencies.isPreferredDeviceReachable?() ?? false)
	}

	private static func shouldShowConnectingAtRecoveryStart(
		request: ConnectivityRecoveryRequest,
		dependencies: Dependencies
	) async -> Bool {
		if request.localPathsFailed { return true }
		guard request.skipInitialProbe else { return true }
		guard await dependencies.currentDeviceAccess() == .connected else { return true }
		return !(await preferredDeviceIsReachable(dependencies))
	}

	private static func requiresRAAuthentication(
		localPathsAllowed: Bool,
		localProbeFailed: Bool,
		dependencies: Dependencies
	) async -> Bool {
		guard let remoteAccessService = dependencies.remoteAccessService else { return false }
		guard await remoteAccessService.hasValidTokens() == false else { return false }
		return needsRemoteAccessForRecovery(
			localPathsAllowed: localPathsAllowed,
			localProbeFailed: localProbeFailed,
			dependencies: dependencies
		)
	}

	private static func needsRemoteAccessForRecovery(
		localPathsAllowed: Bool,
		localProbeFailed: Bool,
		dependencies: Dependencies
	) -> Bool {
		guard let preferences = dependencies.preferences else { return localProbeFailed || !localPathsAllowed }
		let paths = pathsForConnectedDevice(preferences: preferences)
		if paths.isEmpty {
			// mDNS-only / no saved WAN paths — RA cannot help on the same LAN.
			return !localPathsAllowed
		}
		if paths.allSatisfy({ $0.kind == .local }) {
			return !localPathsAllowed
		}
		if !localPathsAllowed { return true }
		return localProbeFailed
	}

	static func recoveryEmail(preferences: HCPreferences?) -> String? {
		if let email = preferences?.favoriteEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !email.isEmpty {
			return email
		}
		if let userName = OCBookmarkManager.shared.bookmarks.first?.userName?
			.trimmingCharacters(in: .whitespacesAndNewlines),
		   !userName.isEmpty,
		   userName.contains("@") {
			return userName
		}
		return nil
	}

	private static func pathsForConnectedDevice(preferences: HCPreferences) -> [RemoteDevice.Path] {
		guard let saved = preferences.currentConnectedDevice else { return [] }
		return saved.paths.map { $0.asRemotePath() }.ordered()
	}

	private static func merging(
		_ paths: [RemoteDevice.Path],
		with supplemental: [RemoteDevice.Path]
	) -> [RemoteDevice.Path] {
		var seen = Set(paths.map(\.key))
		var merged = paths
		for path in supplemental where seen.insert(path.key).inserted {
			merged.append(path)
		}
		return merged.ordered()
	}
}
