import Foundation
import Network
import Combine
import RegexBuilder

public struct LocalDevice {
    public let name: String
    public let host: String
    public let port: Int
    public let certificateCommonName: String?
	public let oobeIsDone: Bool
}

private enum Constants {
	static let mDNSServiceType = "_https._tcp"
	static func isHomeCloud(_ name: String) -> Bool {
		name.range(of: "homecloud", options: [.caseInsensitive]) != nil
	}
}

public final class MDNSService {
	public static var shared = MDNSService()
	private var browser: NWBrowser?

	private var results: [LocalDevice] = []
	public var onUpdate: (([LocalDevice]) -> Void)?

	// MARK: - Combine stream
	private let discoveredSubject = PassthroughSubject<LocalDevice, Never>()
	private let devicesSubject = CurrentValueSubject<[LocalDevice], Never>([])
	public var devicesPublisher: AnyPublisher<[LocalDevice], Never> { devicesSubject.eraseToAnyPublisher() }
	private var cancellables = Set<AnyCancellable>()

	public func start() {
		let descriptor = NWBrowser.Descriptor.bonjour(type: Constants.mDNSServiceType, domain: nil)
		let params = NWParameters()
		params.includePeerToPeer = true

		let browser = NWBrowser(for: descriptor, using: params)
		self.browser = browser

		browser.stateUpdateHandler = { state in
			Log.debug("[STX-MDNS]: Browser state: \"\(state)\"")
		}

		browser.browseResultsChangedHandler = { results, changes in
			for result in results {
				if case let .service(name: name, type: _, domain: _, interface: _) = result.endpoint {
					guard Constants.isHomeCloud(name) else { return }

					self.resolve(result: result)
					Log.debug("[STX-MDNS]: Found service: \"\(name)\"")
				}
			}
		}

		browser.start(queue: .main)

		discoveredSubject
			.flatMap { [weak self] device -> AnyPublisher<LocalDevice, Never> in
				guard let self else { return Just(device).eraseToAnyPublisher() }

				return self.aboutPublisher(for: device)
			}
			.receive(on: DispatchQueue.main)
			.sink { [weak self] updated in
				guard let self else { return }

				self.upsert(updated)
				self.onUpdate?(results)
				self.devicesSubject.send(results)
			}
			.store(in: &cancellables)
	}

	public func stop() {
		browser?.cancel()
		browser = nil
	}

	public func currentDevices() -> [LocalDevice] {
		results
	}

	private func resolve(result: NWBrowser.Result) {
		guard case let .service(name, type, domain, _) = result.endpoint else { return }
		let params = NWParameters.tcp
		let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
		let conn = NWConnection(to: endpoint, using: params)
		conn.stateUpdateHandler = { state in
			if case .ready = state {
				if case let .hostPort(host, port) = conn.currentPath?.remoteEndpoint {
					let portValue = Int(port.rawValue)
					let hostString: String?

					switch host {
						case let .ipv4(addr):
							hostString = addr.string

						case let .ipv6(addr):
							hostString = addr.string

						case let .name(name, _):
							hostString = name

						@unknown default:
							hostString = nil
					}
					guard let hostString else {
						Log.debug("[STX-MDNS]: Host is empty for \(host), ignoring.")
						return
					}
					Log.debug("[STX-MDNS]: Resolved \"\(name)\" to \"\(hostString):\(port)\"")
					let entry = LocalDevice(
						name: name,
						host: hostString,
						port: portValue,
						certificateCommonName: nil,
						oobeIsDone: false
					)
					self.upsert(entry)
					self.discoveredSubject.send(entry)
				}
				conn.cancel()
			}
		}
		conn.start(queue: .main)
	}

	private func upsert(_ entry: LocalDevice) {
		if let idx = results.firstIndex(where: { $0.name == entry.name }) {
			results[idx] = entry
		} else {
			results.append(entry)
		}
	}

	private func aboutPublisher(for device: LocalDevice) -> AnyPublisher<LocalDevice, Never> {
		Future<LocalDevice, Never> { promise in
			Task {
				do {
					guard let baseURL = URL(string: "https://\(device.host):\(device.port)/api/v1/") else {
						promise(.success(device))
						return
					}

					let api = DeviceAPI(baseURL: baseURL)
					// First check status to ensure OOBE is done
					let status = try await api.getStatus()

					// Then fetch about when ready
					let about = try await api.getAbout()
					promise(.success(LocalDevice(
						name: device.name,
						host: device.host,
						port: device.port,
						certificateCommonName: about.certificate_common_name,
						oobeIsDone: status.OOBE.done
					)))
				} catch {
					Log.debug("[STX-MDNS]: Got error resolving device: \(error)")
					promise(.success(device))
				}
			}
		}.eraseToAnyPublisher()
	}
}
