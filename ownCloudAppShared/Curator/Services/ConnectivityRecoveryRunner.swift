import Foundation
import ownCloudSDK

/// The single connectivity evaluator. Serializes concurrent requests, then:
///   1. probes every configured path and selects the best reachable one (local > public > remote),
///   2. switches the SDK base URL directly when a better reachable path is found,
///   3. only falls back to a full catalog reload (discovery) when nothing responded,
///   4. attempts remote-access re-authentication when required,
///   5. otherwise reports the device as disconnected (the "Retry" banner).
///
/// This runner is the *only* writer of `DeviceAccessState`, which is why no access-policy
/// arbitration is needed any more.
final class ConnectivityRecoveryRunner {
	struct Dependencies {
		let pathProber: PathProber
		var preferences: HCPreferences?
		var remoteAccessService: RemoteAccessService?
		var allProbePaths: (() async -> [RemoteDevice.Path])?
		var isPreferredDeviceReachable: (() async -> Bool)?
		var pathRecoveryHandler: (() async throws -> Void)?
		var configuredProbePaths: ((HCPreferences) async -> [RemoteDevice.Path])?
		var applyBestProbedPath: (@Sendable (RemoteDevice.Path) async -> Void)?
		var requestRAAuthentication: ((String) async -> Bool)?
		var recoveryEmail: () -> String?
		var applyDeviceAccess: @Sendable (DeviceAccessState) async -> Void
		var beginRemoteAuthentication: @Sendable () async -> Void
		var endRemoteAuthentication: @Sendable (DeviceAccessState) async -> Void
		var log: (String) -> Void
	}

	private(set) var task: Task<Void, Never>?
	private var pendingLocalPathsAllowed: Bool?

	var isInFlight: Bool { task != nil }

	func reset() {
		task?.cancel()
		task = nil
		pendingLocalPathsAllowed = nil
	}

	func run(
		localPathsAllowed: Bool,
		session: ConnectivitySessionState,
		snackbarDrivingEnabled: Bool,
		dependencies: Dependencies,
		perform: @escaping @Sendable (Bool, Dependencies, ConnectivitySessionState, Bool) async -> Void
	) async {
		if let inFlight = task {
			pendingLocalPathsAllowed = localPathsAllowed
			dependencies.log("evaluate coalesced with in-flight run")
			await inFlight.value
			return
		}

		var localAllowed = localPathsAllowed
		repeat {
			dependencies.log("evaluate started (localAllowed=\(localAllowed))")
			task = Task {
				await perform(localAllowed, dependencies, session, snackbarDrivingEnabled)
			}
			await task?.value
			task = nil

			guard let pending = pendingLocalPathsAllowed else { break }
			pendingLocalPathsAllowed = nil
			localAllowed = pending
		} while true
	}

	static func performEvaluate(
		_ localPathsAllowed: Bool,
		dependencies: Dependencies,
		session: ConnectivitySessionState,
		snackbarDrivingEnabled: Bool
	) async {
		switch session.checkRecoveryEligibility() {
			case .eligible:    break
			case .ineligible:  return
		}
		if Task.isCancelled { return }

		if snackbarDrivingEnabled {
			await dependencies.applyDeviceAccess(.connecting)
		}

		guard let preferences = dependencies.preferences else {
			await dependencies.applyDeviceAccess(.disconnected)
			return
		}

		let paths = await configuredProbePaths(preferences: preferences, dependencies: dependencies)
		let currentPathKey = preferences.currentConnectedDevice?.lastSuccessfulPathKey

		if !paths.isEmpty {
			let outcome = await dependencies.pathProber.probeAndSelectBest(
				paths: paths,
				currentPathKey: currentPathKey,
				localPathsAllowed: localPathsAllowed
			)
			ConnectivityEventLog.probeOutcome(
				outcome,
				pathCount: paths.count,
				currentPathKey: currentPathKey,
				localPathsAllowed: localPathsAllowed
			)

			switch outcome {
				case .currentIsBest:
					dependencies.log("probe→keep current path")
					await dependencies.applyDeviceAccess(.connected)
					return
				case .betterPath(let path):
					// The probe already verified `path` is reachable, so switch the SDK base
					// URL directly instead of triggering a slow full catalog reload.
					dependencies.log("probe→switch to better path (\(path.key))")
					await dependencies.applyBestProbedPath?(path)
					await dependencies.applyDeviceAccess(.connected)
					return
				case .noneReachable:
					dependencies.log("probe→no path reachable")
			}
		} else {
			dependencies.log("probe→no paths configured")
		}

		// Nothing responded with the known paths — run discovery (full catalog reload, which
		// re-probes everything) and trust the freshly-probed catalog for the verdict.
		await invokePathRecoveryHandler(dependencies: dependencies)
		if await preferredDeviceIsReachable(dependencies) {
			dependencies.log("reload→connected")
			await dependencies.applyDeviceAccess(.connected)
			return
		}

		if await tryRemoteAuthentication(localPathsAllowed: localPathsAllowed, dependencies: dependencies) {
			return
		}

		dependencies.log("evaluate→disconnected (retry)")
		await dependencies.applyDeviceAccess(.disconnected)
	}

	// MARK: - Remote-access re-authentication

	private static func tryRemoteAuthentication(
		localPathsAllowed: Bool,
		dependencies: Dependencies
	) async -> Bool {
		guard await requiresRAAuthentication(
			localPathsAllowed: localPathsAllowed,
			dependencies: dependencies
		) else {
			dependencies.log("RA skipped (localAllowed=\(localPathsAllowed))")
			return false
		}

		dependencies.log("evaluate requires RA authentication")
		guard let email = dependencies.recoveryEmail() else {
			Log.debug("[STX-RA]: RA tokens missing but no email available for verification.")
			return false
		}
		Log.debug("[STX-RA]: Requesting RA verification for \(email).")
		await dependencies.beginRemoteAuthentication()
		let authenticated = await dependencies.requestRAAuthentication?(email) ?? false
		if Task.isCancelled {
			await dependencies.endRemoteAuthentication(.connecting)
			return true
		}
		if !authenticated {
			dependencies.log("RA auth failed")
			await dependencies.endRemoteAuthentication(.disconnected)
			return false
		}
		await dependencies.endRemoteAuthentication(.connecting)
		dependencies.log("RA auth succeeded — reloading paths")
		await invokePathRecoveryHandler(dependencies: dependencies)
		if await preferredDeviceIsReachable(dependencies) {
			dependencies.log("RA reload→connected")
			await dependencies.applyDeviceAccess(.connected)
		} else {
			dependencies.log("RA reload→disconnected (retry)")
			await dependencies.applyDeviceAccess(.disconnected)
		}
		return true
	}

	// MARK: - Probe helpers

	static func configuredProbePaths(
		preferences: HCPreferences,
		dependencies: Dependencies
	) async -> [RemoteDevice.Path] {
		if let resolver = dependencies.configuredProbePaths {
			return await resolver(preferences)
		}
		return await dependencies.allProbePaths?() ?? pathsForConnectedDevice(preferences: preferences)
	}

	private static func invokePathRecoveryHandler(dependencies: Dependencies) async {
		guard let handler = dependencies.pathRecoveryHandler else { return }
		do {
			try await handler()
		} catch {
			ConnectivityEventLog.recoveryFailure("catalog reload", error: error)
		}
	}

	private static func preferredDeviceIsReachable(_ dependencies: Dependencies) async -> Bool {
		await (dependencies.isPreferredDeviceReachable?() ?? false)
	}

	private static func requiresRAAuthentication(
		localPathsAllowed: Bool,
		dependencies: Dependencies
	) async -> Bool {
		guard let remoteAccessService = dependencies.remoteAccessService else { return false }
		guard await remoteAccessService.hasValidTokens() == false else { return false }
		return needsRemoteAccessForRecovery(
			localPathsAllowed: localPathsAllowed,
			dependencies: dependencies
		)
	}

	private static func needsRemoteAccessForRecovery(
		localPathsAllowed: Bool,
		dependencies: Dependencies
	) -> Bool {
		// At this point the local/known probes already failed, so remote access is the only
		// remaining way in unless every configured path is local and we are on the LAN.
		guard let preferences = dependencies.preferences else { return true }
		let paths = pathsForConnectedDevice(preferences: preferences)
		if paths.isEmpty {
			return true
		}
		if paths.allSatisfy({ $0.kind == .local }) {
			return !localPathsAllowed
		}
		return true
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
}
