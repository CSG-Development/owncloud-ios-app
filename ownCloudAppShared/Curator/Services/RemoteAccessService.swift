import Foundation
import UIKit

public struct RemoteDevice {
	public let seagateDeviceID: String
	public let friendlyName: String
	public let hostname: String
	public let certificateCommonName: String
	public let paths: [Path]

	public struct Path {
		public enum Kind {
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
    public static let shared = RemoteAccessService()

	private enum Constants {
		static let baseURL = URL(
			string: "https://hc-remote-access-env-https.eba-a2nvhpbm.us-west-2.elasticbeanstalk.com:443/api"
		)!

		static var clientId: String {
			UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
		}

		static var clientFriendlyName: String {
			UIDevice.current.name
		}
	}

	private var store: RemoteAccessTokenStore {
		RemoteAccessTokenStore.shared
	}
    private var api: RemoteAccessAPI

	private var referenceEmailMap: [String: String] = [:]

    private init() {
		self.api = RemoteAccessAPI(baseURL: Constants.baseURL)
    }

	private func saveTokens(for email: String, response: RATokenResponse) {
		let raToken = RemoteAccessToken(raTokenResponse: response)
		_ = store.save(tokens: raToken, for: email)
	}

	public func ensureAuthenticated(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
		Task {
			do {
				try await refreshTokensIfNeeded(for: email)
				await MainActor.run { completion(.success(())) }
			} catch {
				await MainActor.run { completion(.failure(error)) }
			}
		}
	}

	private func refreshTokensIfNeeded(for email: String) async throws {
		guard
			let tokens = store.loadTokens(for: email),
			!tokens.refreshToken.isEmpty
		else {
			_ = RemoteAccessTokenStore.shared.clear(email: email)
			throw RemoteAccessServiceError.unauthorized
		}

		let refreshTokens = {
			let response = try await self.api.refreshAccessToken(refreshToken: tokens.refreshToken)
			self.saveTokens(for: email, response: response)
			self.api.accessToken = tokens.accessToken
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
				guard let email = referenceEmailMap[reference] else {
					throw RemoteAccessServiceError.noEmailForReference
				}
                let response = try await api.validateEmailCode(code: code, reference: reference)
				saveTokens(for: email, response: response)
                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

	public func getRemoteDevices(
		email: String,
		completion: @escaping (Result<[RemoteDevice], Error>) -> Void
	) {
		Task {
			do {
				try await refreshTokensIfNeeded(for: email)

				var mRemoteDevices: [RemoteDevice] = []
				let devices = try await api.listDevices()
				for device in devices {
					let paths = try await api.getDevicePaths(
						deviceID: device.seagateDeviceID
					)
					mRemoteDevices.append(RemoteDevice(raDevice: device, raDevicePaths: paths))
				}
				let remoteDevices = mRemoteDevices
				await MainActor.run { completion(.success(remoteDevices)) }
			} catch {
				await MainActor.run { completion(.failure(error)) }
			}
		}
	}
}
