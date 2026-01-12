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
	private let tokenStore: RemoteAccessTokenStore
	private let client: RemoteAccessClient

	public init(
		api: RemoteAccessAPI,
		tokenStore: RemoteAccessTokenStore
	) {
		self.api = api
		self.tokenStore = tokenStore
		self.client = RemoteAccessClient(api: api, tokenStore: tokenStore)
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
                try await client.validateEmailCode(
					code: code,
					clientId: Constants.clientId,
					reference: reference
				)
                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

	public func getRemoteDevices(email: String) async throws -> [RemoteDevice] {
		let apiDevices = try await client.listDevices(clientId: Constants.clientId)
		return try await withThrowingTaskGroup(of: RemoteDevice.self) { group in
			for device in apiDevices {
				group.addTask {
					let paths = try await self.client.getDevicePaths(clientId: Constants.clientId, deviceID: device.seagateDeviceID)
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

	public func hasValidTokens() async -> Bool {
		await client.hasValidTokens(clientId: Constants.clientId)
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

	public func clearTokens() {
		Task {
			await client.clearTokens()
		}
	}
}
