import FlyingFox
import FlyingSocks
import Foundation

public final class StreamingProxyServer: NSObject {
	public static let shared = StreamingProxyServer(certificateValidator: CertificateValidationService.shared)

	private let resourceStore = ProxyResourceStore()
	private let certificateValidator: CertificateValidator
	private let queue = DispatchQueue(label: "com.owncloud.streaming-proxy.server", qos: .userInitiated)
	private var expirationTimer: DispatchSourceTimer?
	private var serverBox: ServerBox?

	public init(certificateValidator: CertificateValidator) {
		self.certificateValidator = certificateValidator
		super.init()
	}

	deinit {
		stop()
	}

	public func start() throws -> UInt16 {
		try queue.sync {
			if let box = serverBox { return box.port }
			return try startServer()
		}
	}

	private func startServer() throws -> UInt16 {
		let address = try sockaddr_in.inet(ip4: "127.0.0.1", port: 0)
		let server = HTTPServer(address: address, timeout: 120, logger: .disabled)

		let semaphore = DispatchSemaphore(value: 0)
		var port: UInt16 = 0
		var startupError: Error?

		let task = Task { [weak self] in
			do {
				await server.appendRoute("GET,HEAD /proxy/:id") { [weak self] request in
					await self?.handleRequest(request) ?? HTTPResponse(statusCode: .internalServerError)
				}
				let runTask = Task { try await server.run() }
				try await server.waitUntilListening()

				if let address = await server.listeningAddress {
					port = Self.port(from: address)
				}

				semaphore.signal()
				try await runTask.value
			} catch {
				if port == 0 {
					startupError = error
					semaphore.signal()
				}
			}
		}

		semaphore.wait()

		if let startupError {
			task.cancel()
			throw startupError
		}

		guard port > 0 else {
			task.cancel()
			throw StreamingProxyError.unableToStartListener
		}

		serverBox = ServerBox(server: server, task: task, port: port)
		startExpirationTimer()
		return port
	}

	public func stop() {
		queue.sync {
			guard let box = serverBox else { return }
			serverBox = nil
			expirationTimer?.cancel()
			expirationTimer = nil
			box.task.cancel()
			Task { await box.server.stop(timeout: 3) }
		}
	}

	public func register(remoteURL: URL, headers: [String: String]?) -> URL {
		let port: UInt16
		do { port = try start() } catch { return remoteURL }

		guard let baseURL = URL(string: "http://127.0.0.1:\(port)/") else { return remoteURL }

		return resourceStore.register(remoteURL: remoteURL, headers: headers ?? [:], proxyBaseURL: baseURL)
	}

	public func remove(proxyURL: URL) {
		queue.async { [resourceStore] in
			resourceStore.remove(proxyURL: proxyURL)
		}
	}

	private func startExpirationTimer() {
		let timer = DispatchSource.makeTimerSource(queue: queue)
		timer.schedule(deadline: .now() + 60, repeating: 60)
		timer.setEventHandler { [weak self] in self?.resourceStore.removeExpiredResources() }
		timer.resume()
		expirationTimer = timer
	}

	private func handleRequest(_ request: HTTPRequest) async -> HTTPResponse {
		guard let resourceID = request.routeParameters["id"].flatMap({ UUID(uuidString: $0) }),
			  let resource = resourceStore.resolve(id: resourceID) else {
			return HTTPResponse(statusCode: .notFound)
		}

		var clientHeaders: [String: String] = [:]
		for (name, value) in request.headers {
			clientHeaders[name.rawValue.lowercased()] = value
		}

		return await ProxyStreamBridge(
			resource: resource,
			requestMethod: request.method.rawValue,
			clientHeaders: clientHeaders,
			certificateValidator: certificateValidator
		).handle()
	}

	private static func port(from address: Socket.Address) -> UInt16 {
		switch address {
		case .ip4(_, let port), .ip6(_, let port): return port
		case .unix: return 0
		}
	}

	private struct ServerBox {
		let server: HTTPServer
		let task: Task<Void, Never>
		let port: UInt16
	}
}

public enum StreamingProxy {
	public static func shouldProxy(remoteURL: URL, requiresLocalCopy: Bool) -> Bool {
		guard !requiresLocalCopy else { return false }
		guard !remoteURL.isFileURL else { return false }
		guard remoteURL.scheme?.lowercased() == "https" else { return false }
		return true
	}
}

private struct StreamingProxyError: LocalizedError {
	let errorDescription: String?
	static let unableToStartListener = StreamingProxyError(errorDescription: "Streaming proxy failed to acquire a listening port")
}
