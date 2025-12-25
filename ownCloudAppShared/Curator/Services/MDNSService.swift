import Foundation
import Network
import Combine
import RegexBuilder

public struct LocalDevice: Sendable, Codable {
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
	private var browser: NWBrowser?

	private var results: [LocalDevice] = []
	public var onUpdate: (([LocalDevice]) -> Void)?

	// MARK: - Combine stream
	private let discoveredSubject = PassthroughSubject<LocalDevice, Never>()
	private let devicesSubject = CurrentValueSubject<[LocalDevice], Never>([])
	public var devicesPublisher: AnyPublisher<[LocalDevice], Never> { devicesSubject.eraseToAnyPublisher() }
	private var cancellables = Set<AnyCancellable>()

	public init() {}

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
		var emitted = false
		func emit(_ entry: LocalDevice) {
			guard emitted == false else { return }
			emitted = true
			self.upsert(entry)
			self.discoveredSubject.send(entry)
		}
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
					// Accept only IPv4 non-link-local; otherwise try Wi‑Fi-only resolve
					if self.isIPv4(hostString) && self.isLinkLocal(hostString) == false {
						emit(LocalDevice(
						name: name,
						host: hostString,
						port: portValue,
						certificateCommonName: nil,
						oobeIsDone: false
						))
					} else {
						// Try Wi‑Fi-only to get an IPv4 non-link-local address
						let wifiParams = NWParameters.tcp
						wifiParams.requiredInterfaceType = .wifi
						let wifiConn = NWConnection(to: endpoint, using: wifiParams)
						wifiConn.stateUpdateHandler = { wifiState in
							if case .ready = wifiState {
								if case let .hostPort(wifiHost, wifiPort) = wifiConn.currentPath?.remoteEndpoint {
									let wifiPortValue = Int(wifiPort.rawValue)
									let wifiHostString: String?
									switch wifiHost {
										case let .ipv4(addr):
											wifiHostString = addr.string
										case let .ipv6(addr):
											wifiHostString = addr.string
										case let .name(name, _):
											wifiHostString = name
										@unknown default:
											wifiHostString = nil
									}
									if let wifiHostString, self.isIPv4(wifiHostString), self.isLinkLocal(wifiHostString) == false {
										Log.debug("[STX-MDNS]: Preferred IPv4 Wi‑Fi address for \"\(name)\" -> \"\(wifiHostString):\(wifiPort)\"")
										emit(LocalDevice(
											name: name,
											host: wifiHostString,
											port: wifiPortValue,
											certificateCommonName: nil,
											oobeIsDone: false
										))
										wifiConn.cancel()
										return
									}
								}
								// Wi‑Fi gave no IPv4 non-link-local; do not emit
								wifiConn.cancel()
							} else if case .failed = wifiState {
								// Fallback failed; do not emit
							}
						}
						// Safety timeout for fallback
						DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
							wifiConn.cancel()
						}
						wifiConn.start(queue: .main)
					}
				}
				conn.cancel()
			}
		}
		conn.start(queue: .main)
	}

	private func isLinkLocal(_ host: String) -> Bool {
		// IPv4 link-local: 169.254.0.0/16
		if host.hasPrefix("169.254.") { return true }
		// IPv6 link-local typically starts with fe80::/10 (allowing fe8, fe9, fea, feb)
		let lower = host.lowercased()
		if lower.hasPrefix("fe80:") || lower.hasPrefix("fe80::") { return true }
		return false
	}
	
	private func isIPv4(_ host: String) -> Bool {
		// Simple heuristic: contains exactly 3 dots and all octets are digits
		let parts = host.split(separator: ".")
		if parts.count != 4 { return false }
		for p in parts {
			if p.isEmpty || p.contains(where: { $0 < "0" || $0 > "9" }) { return false }
		}
		return true
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
