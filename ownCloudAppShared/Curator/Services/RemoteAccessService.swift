import Foundation
import UIKit

public struct RemoteDevice: Sendable, Codable {
	public let seagateDeviceID: String
	public let friendlyName: String
	public let hostname: String
	public let certificateCommonName: String
	public let paths: [Path]

	public struct Path: Sendable, Codable {
		public enum Kind: String, Sendable, Codable {
			case local
			case `public`
			case remote

			init(raDevicePathKind: RADevicePathKind) {
				self = switch raDevicePathKind {
					case .local: .local
					case .`public`: .`public`
					case .remote: .remote
				}
			}
		}

		public let kind: Kind
		public let address: String
		public let port: Int?

		init(raDevicePath: RADevicePath) {
			self.kind = Kind(raDevicePathKind: raDevicePath.type)
			self.address = raDevicePath.address
			self.port = raDevicePath.port
		}
	}

	public init(
		seagateDeviceID: String,
		friendlyName: String,
		hostname: String,
		certificateCommonName: String,
		paths: [Path]
	) {
		self.seagateDeviceID = seagateDeviceID
		self.friendlyName = friendlyName
		self.hostname = hostname
		self.certificateCommonName = certificateCommonName
		self.paths = paths
	}

	init(
		raDevice: RADevice,
		raDevicePaths: RADevicePaths
	) {
		self.init(
			seagateDeviceID: raDevice.seagateDeviceID,
			friendlyName: raDevice.friendlyName,
			hostname: raDevice.hostname,
			certificateCommonName: raDevice.certificateCommonName,
			paths: raDevicePaths.paths.map { Path(raDevicePath: $0) }
		)
	}
}

enum RemoteAccessServiceError: Error {
	case noEmailForReference
	case unauthorized
}

public final class RemoteAccessService {
	private enum Constants {
		static var clientId: String {
			UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
		}

		static var clientFriendlyName: String {
			UIDevice.current.name
		}
	}

    private var api: RemoteAccessAPI

	private var referenceEmailMap: [String: String] = [:]
	private let tokenStore: RemoteAccessTokenStore

	public init(
		api: RemoteAccessAPI,
		tokenStore: RemoteAccessTokenStore
	) {
		self.api = api
		self.tokenStore = tokenStore
    }

	private func saveTokens(response: RATokenResponse) {
		let tokens = RemoteAccessToken(raTokenResponse: response)
		_ = tokenStore.save(tokens)
	}

	public func ensureAuthenticated(
		email: String,
		completion: @escaping (Result<Void, Error>) -> Void
	) {
		Task {
			do {
				try await refreshTokensIfNeeded()
				await MainActor.run { completion(.success(())) }
			} catch {
				await MainActor.run { completion(.failure(error)) }
			}
		}
	}

	private func refreshTokensIfNeeded() async throws {
		guard
			let tokens = tokenStore.loadTokens(),
			!tokens.refreshToken.isEmpty
		else {
			_ = tokenStore.clear()
			throw RemoteAccessServiceError.unauthorized
		}

		let refreshTokens = {
			do {
				let response = try await self.api.refreshAccessToken(refreshToken: tokens.refreshToken)
				self.saveTokens(response: response)
				self.api.accessToken = tokens.accessToken
			} catch {
				if let ns = error as NSError?, ns.domain == "RemoteAccessAPI", (400...499).contains(ns.code) {
					_ = self.tokenStore.clear()
					throw RemoteAccessServiceError.unauthorized
				}
				throw error
			}
		}

		guard let expiry = tokens.accessTokenExpiry else {
			try await refreshTokens()
			return
		}

		if Date() > expiry {
			try await refreshTokens()
		}
		self.api.accessToken = tokens.accessToken
	}

    public func sendEmailCode(
        email: String,
        completion: @escaping (Result<RAInitiateResponse, Error>) -> Void
    ) {
        Task {
            do {
                let response = try await api.sendEmailCode(
                    email: email,
					clientId: Constants.clientId,
					clientFriendlyName: Constants.clientFriendlyName
                )
				referenceEmailMap[response.reference] = email
                await MainActor.run { completion(.success(response)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    public func validateEmailCode(
        code: String,
        reference: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task {
            do {
                let response = try await api.validateEmailCode(
					code: code,
					clientId: Constants.clientId,
					reference: reference
				)
				saveTokens(response: response)
                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

	public func getRemoteDevices(email: String) async throws -> [RemoteDevice] {
		try await refreshTokensIfNeeded()

		let apiDevices = try await api.listDevices()
		return try await withThrowingTaskGroup(of: RemoteDevice.self) { group in
			for device in apiDevices {
				group.addTask {
					let paths = try await self.api.getDevicePaths(deviceID: device.seagateDeviceID)
					return RemoteDevice(raDevice: device, raDevicePaths: paths)
				}
			}

			var gathered: [RemoteDevice] = []
			for try await item in group {
				gathered.append(item)
			}
			return gathered
		}
	}

	public func clearTokens() {
		_ = tokenStore.clear()
	}

	public func hasValidTokens() async -> Bool {
		do {
			try await refreshTokensIfNeeded()
			return true
		} catch {
			if let raError = error as? RemoteAccessServiceError, raError == .unauthorized {
				return false
			}
			if let ns = error as NSError?, ns.domain == "RemoteAccessAPI", (400...499).contains(ns.code) {
				_ = tokenStore.clear()
				return false
			}
			if let urlError = error as? URLError {
				Log.debug("[STX-RA]: hasValidTokens transient URL error: \(urlError)")
				return true
			}
			return true
		}
	}

	@discardableResult
	public func getRemoteDevices(
		email: String,
		callbackQueue: DispatchQueue = .main,
		completion: @escaping (Result<[RemoteDevice], Error>) -> Void
	) -> Task<Void, Never> {
		Task {
			let result: Result<[RemoteDevice], Error>
			do {
				let devices = try await getRemoteDevices(email: email)
				result = .success(devices)
			} catch {
				result = .failure(error)
			}
			callbackQueue.async {
				completion(result)
			}
		}
	}
}
