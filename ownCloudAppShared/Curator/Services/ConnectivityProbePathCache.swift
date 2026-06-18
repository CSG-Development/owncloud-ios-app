import Foundation
import ownCloudSDK

/// Caches configured probe paths until the device catalog or saved paths change.
final class ConnectivityProbePathCache {
	private struct Entry {
		let key: String
		let paths: [RemoteDevice.Path]
	}

	private var entry: Entry?

	func invalidate() {
		entry = nil
	}

	func configuredPaths(
		preferences: HCPreferences,
		supplementalProbePaths: () async -> [RemoteDevice.Path]
	) async -> [RemoteDevice.Path] {
		let key = Self.cacheKey(for: preferences)
		if let entry, entry.key == key {
			return entry.paths
		}

		var paths = Self.pathsForConnectedDevice(preferences: preferences)
		let supplemental = await supplementalProbePaths()
		paths = Self.merging(paths, with: supplemental)
		entry = Entry(key: key, paths: paths)
		return paths
	}

	static func cacheKey(for preferences: HCPreferences) -> String {
		guard let saved = preferences.currentConnectedDevice else { return "none" }
		let pathKeys = saved.paths.map(\.pathKey).sorted().joined(separator: "|")
		return "\(saved.certificateCommonName)|\(saved.lastSuccessfulPathKey ?? "")|\(pathKeys)"
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
