public struct AnySendableError: Error, Sendable {
	public let underlying: any Error
	
	public init(_ underlying: any Error) {
		self.underlying = underlying
	}
}
