import Foundation
import UIKit

public enum PublicLinkRemoteAccessResult {
	case available
	case cancelled
	case unavailable
}

public enum RemoteAccessSharingURLResolver {
	public static func resolveRemoteSharingURLSync(for url: URL?) -> URL? {
		guard let url, let remoteBaseURL = HCContext.shared.lastRemoteBaseURL else { return nil }
		return RemoteAccessSharingURLResolver.applyRemoteBase(remoteBaseURL, to: url)
	}

	public static func resolveRemoteSharingURL(
		for url: URL,
		completion: @escaping (URL?) -> Void
	) {
		Task {
			let resolved = await resolveRemoteSharingURL(for: url)
			await MainActor.run {
				completion(resolved)
			}
		}
	}

	public static func resolveRemoteSharingURL(for url: URL) async -> URL? {
		let deviceService = HCContext.shared.deviceReachabilityService

		if let remoteBaseURL = await deviceService.currentRemoteBaseURL(),
		   let adjusted = applyRemoteBase(remoteBaseURL, to: url) {
			return adjusted
		}

		guard let email = HCContext.shared.preferences.favoriteEmail else {
			return nil
		}

		let hasTokens = await HCContext.shared.remoteAccessService.hasValidTokens()
		if hasTokens == false {
			Log.debug("[STX-RA]: Has no valid tokens. Requesting email verification.")
			let authenticated = await requestEmailVerification(email: email)
			guard authenticated else { return nil }
		}

		await deviceService.forceReloadDevices()

		guard let remoteBaseURL = await deviceService.currentRemoteBaseURL() else {
			return nil
		}
		return applyRemoteBase(remoteBaseURL, to: url)
	}

	private static func applyRemoteBase(_ baseURL: URL, to url: URL) -> URL? {
		let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
		guard var updatedComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return nil
		}

		let scheme = baseComponents?.scheme ?? updatedComponents.scheme
		let host = baseComponents?.host ?? updatedComponents.host
		let port = baseComponents?.port

		updatedComponents.scheme = scheme
		updatedComponents.host = host
		updatedComponents.port = port

		return updatedComponents.url
	}

	/// Confirms with the user, then runs Remote Access pairing if the device has no remote path.
	@MainActor
	public static func ensureRemotePathForPublicLinks(from presenter: UIViewController) async -> PublicLinkRemoteAccessResult {
		if await hasRemotePath() {
			return .available
		}

		// Remote Access is already paired, so pairing it again cannot produce a remote link:
		// offering the "enable" prompt here would just loop the user through a no-op.
		if await HCContext.shared.remoteAccessService.hasValidTokens() {
			return .unavailable
		}

		let confirmed = await confirmRemoteAccessRequired(from: presenter)
		guard confirmed else { return .cancelled }

		let authenticated = await enableRemoteAccess()
		guard authenticated else { return .cancelled }

		if await currentRemoteBaseURL() != nil {
			return .available
		}
		return .unavailable
	}

	public static func currentRemoteBaseURL() async -> URL? {
		await HCContext.shared.deviceReachabilityService.currentRemoteBaseURL()
	}

	/// Returns whether a remote path is already known, reloading the catalog when RA tokens exist.
	public static func hasRemotePath() async -> Bool {
		if await currentRemoteBaseURL() != nil {
			return true
		}

		let hasTokens = await HCContext.shared.remoteAccessService.hasValidTokens()
		guard hasTokens else { return false }

		return await refreshRemoteBaseURL() != nil
	}

	/// Reloads connection paths and publishes the resulting remote base URL, if any.
	@discardableResult
	private static func refreshRemoteBaseURL() async -> URL? {
		let deviceService = HCContext.shared.deviceReachabilityService

		// Whenever the device answers on a local path, detection stops before Algorithm A and
		// the RA catalog is never fetched — so pull it explicitly instead of relying on a reload.
		await deviceService.mergeRemoteCatalogAfterLogin()

		if await deviceService.currentRemoteBaseURL() == nil {
			await deviceService.forceReloadDevices()
		}

		guard let url = await deviceService.currentRemoteBaseURL() else {
			Log.debug("[STX-RA]: No remote base URL after refreshing the device catalog.")
			return nil
		}
		await MainActor.run {
			HCContext.shared.lastRemoteBaseURL = url
		}
		return url
	}

	@MainActor
	private static func confirmRemoteAccessRequired(from presenter: UIViewController) async -> Bool {
		await withCheckedContinuation { continuation in
			let alert = ThemedAlertController(
				title: HCL10n.Sharing.remoteAccessRequiredTitle,
				message: HCL10n.Sharing.remoteAccessRequiredMessage,
				preferredStyle: .alert
			)
			alert.addAction(UIAlertAction(title: HCL10n.Common.cancel, style: .cancel, handler: { _ in
				continuation.resume(returning: false)
			}))
			alert.addAction(UIAlertAction(title: HCL10n.Sharing.enableRemoteAccess, style: .default, handler: { _ in
				continuation.resume(returning: true)
			}))
			presenter.present(alert, animated: true)
		}
	}

	/// Pair Remote Access if needed and reload device paths. Returns false if the user cancelled pairing.
	private static func enableRemoteAccess() async -> Bool {
		let hasTokens = await HCContext.shared.remoteAccessService.hasValidTokens()

		if hasTokens == false {
			guard let email = HCContext.shared.preferences.favoriteEmail else {
				return false
			}
			Log.debug("[STX-RA]: Has no valid tokens. Requesting email verification.")
			let authenticated = await requestEmailVerification(email: email)
			guard authenticated else { return false }
		}

		await refreshRemoteBaseURL()
		return true
	}

	private static func requestEmailVerification(email: String) async -> Bool {
		guard let handler = HCContext.shared.emailVerificationHandler else {
			return false
		}

		return await withCheckedContinuation { continuation in
			Task { @MainActor in
				handler(email) { isAuthenticated in
					continuation.resume(returning: isAuthenticated)
				}
			}
		}
	}
}
