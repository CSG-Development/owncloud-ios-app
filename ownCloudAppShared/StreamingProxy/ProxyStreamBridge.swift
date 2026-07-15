import FlyingFox
import FlyingSocks
import Foundation

final class ProxyStreamBridge {
	private let resource: ProxyResource
	private let requestMethod: String
	private let clientHeaders: [String: String]
	private let certificateValidator: CertificateValidator

	init(
		resource: ProxyResource,
		requestMethod: String,
		clientHeaders: [String: String],
		certificateValidator: CertificateValidator
	) {
		self.resource = resource
		self.requestMethod = requestMethod
		self.clientHeaders = clientHeaders
		self.certificateValidator = certificateValidator
	}

	func handle() async -> HTTPResponse {
		let config = URLSessionConfiguration.default
		config.timeoutIntervalForRequest = 120
		config.timeoutIntervalForResource = 0
		config.httpMaximumConnectionsPerHost = 8
		config.requestCachePolicy = .reloadIgnoringLocalCacheData
		config.urlCache = nil
		let session = URLSession(configuration: config)

		var request = URLRequest(url: resource.remoteURL)
		request.httpMethod = requestMethod
		for (name, value) in resource.headers {
			request.setValue(value, forHTTPHeaderField: name)
		}
		for name in ["range", "if-range", "if-modified-since", "if-none-match"] {
			if let value = clientHeaders[name] { request.setValue(value, forHTTPHeaderField: name) }
		}
		if let v = clientHeaders["user-agent"] { request.setValue(v, forHTTPHeaderField: "User-Agent") }
		if let v = clientHeaders["accept"]     { request.setValue(v, forHTTPHeaderField: "Accept") }

		let asyncBytes: URLSession.AsyncBytes
		let urlResponse: URLResponse
		do {
			(asyncBytes, urlResponse) = try await session.bytes(for: request, delegate: TLSTaskDelegate(validator: certificateValidator))
		} catch {
			session.invalidateAndCancel()
			return errorResponse(for: error)
		}

		guard let httpResponse = urlResponse as? HTTPURLResponse else {
			session.invalidateAndCancel()
			return HTTPResponse(statusCode: .badGateway)
		}

		let byteCount = ProxyHTTPMessage.responseBodyByteCount(from: httpResponse)
			?? clientHeaders["range"].flatMap { ProxyHTTPMessage.byteCount(fromRangeHeader: $0) }
		let headers = makeResponseHeaders(from: httpResponse, bodyByteCount: byteCount)
		let statusCode = HTTPStatusCode(httpResponse.statusCode, phrase: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))

		if requestMethod == "HEAD" {
			session.invalidateAndCancel()
			return HTTPResponse(statusCode: statusCode, headers: headers, body: Data())
		}

		// AsyncBytesBufferedSequence keeps `session` alive while FlyingFox streams the body.
		let body = AsyncBytesBufferedSequence(bytes: asyncBytes, session: session, limit: byteCount)
		if let byteCount {
			return HTTPResponse(statusCode: statusCode, headers: headers, body: HTTPBodySequence(from: body, count: byteCount))
		}
		return HTTPResponse(statusCode: statusCode, headers: headers, body: HTTPBodySequence(from: body))
	}

	private func errorResponse(for error: Error) -> HTTPResponse {
		if let urlError = error as? URLError, urlError.code == .cancelled {
			return HTTPResponse(statusCode: .internalServerError)
		}
		let statusCode: HTTPStatusCode = (error as? URLError)?.code == .timedOut ? .gatewayTimeout : .badGateway
		return HTTPResponse(statusCode: statusCode)
	}

	private func makeResponseHeaders(from response: HTTPURLResponse, bodyByteCount: Int?) -> HTTPHeaders {
		var headers = HTTPHeaders()
		for (name, value) in ProxyHTTPMessage.filteredResponseHeaders(from: response) {
			headers[HTTPHeader(name)] = value
		}
		if headers[.acceptRanges] == nil { headers[.acceptRanges] = "bytes" }
		if let bodyByteCount { headers[.contentLength] = String(bodyByteCount) }
		return headers
	}
}

// MARK: - TLS

private final class TLSTaskDelegate: NSObject, URLSessionTaskDelegate {
	private let validator: CertificateValidator

	init(validator: CertificateValidator) {
		self.validator = validator
		super.init()
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
		guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
			  let serverTrust = challenge.protectionSpace.serverTrust else {
			completionHandler(.performDefaultHandling, nil)
			return
		}
		if validator.validate(trust: serverTrust, host: challenge.protectionSpace.host) {
			completionHandler(.useCredential, URLCredential(trust: serverTrust))
		} else {
			completionHandler(.cancelAuthenticationChallenge, nil)
		}
	}
}

// MARK: - Body streaming

private struct AsyncBytesBufferedSequence: AsyncBufferedSequence {
	typealias Element = UInt8
	typealias AsyncIterator = Iterator

	let bytes: URLSession.AsyncBytes
	let session: URLSession  // keeps the session alive while FlyingFox streams the body
	let limit: Int?

	func makeAsyncIterator() -> Iterator { Iterator(inner: bytes.makeAsyncIterator(), remaining: limit) }

	struct Iterator: AsyncBufferedIteratorProtocol {
		typealias Element = UInt8
		typealias Buffer = [UInt8]

		var inner: URLSession.AsyncBytes.AsyncIterator
		var remaining: Int?

		mutating func nextBuffer(suggested count: Int) async throws -> [UInt8]? {
			let readCount = remaining.map { Swift.min($0, count) } ?? count
			guard readCount > 0 else { return nil }

			var buffer = [UInt8]()
			buffer.reserveCapacity(readCount)
			while buffer.count < readCount, let byte = try await inner.next() {
				buffer.append(byte)
			}
			remaining = remaining.map { $0 - buffer.count }
			return buffer.isEmpty ? nil : buffer
		}

		mutating func next() async throws -> UInt8? {
			guard remaining.map({ $0 > 0 }) ?? true else { return nil }
			guard let byte = try await inner.next() else { return nil }
			remaining = remaining.map { $0 - 1 }
			return byte
		}
	}
}
