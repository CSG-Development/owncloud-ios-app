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
		allProbePaths: () async -> [RemoteDevice.Path]
	) async -> [RemoteDevice.Path] {
		let paths = await allProbePaths()
		let key = Self.cacheKey(for: preferences, pathKeys: paths.map(\.key))
		if let entry, entry.key == key {
			return entry.paths
		}
		entry = Entry(key: key, paths: paths)
		return paths
	}

	static func cacheKey(for preferences: HCPreferences, pathKeys: [String]) -> String {
		let cn = preferences.favoriteDeviceCN
			?? preferences.currentConnectedDevice?.certificateCommonName
			?? "none"
		let savedKeys = preferences.currentConnectedDevice?.paths.map(\.pathKey).sorted().joined(separator: "|") ?? ""
		let probeKeys = pathKeys.sorted().joined(separator: "|")
		let lastKey = preferences.currentConnectedDevice?.lastSuccessfulPathKey ?? ""
		return "\(cn)|\(lastKey)|\(savedKeys)|\(probeKeys)"
	}
}
