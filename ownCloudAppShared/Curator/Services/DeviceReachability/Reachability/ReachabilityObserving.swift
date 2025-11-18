import Foundation
import Combine

public protocol ReachabilityObserving {
	/// A Combine publisher of reachability updates.
	var updatesPublisher: AnyPublisher<NetworkState, Never> { get }

	/// The most recently observed state (synchronous snapshot).
	var currentState: NetworkState { get }

	/// Start monitoring (idempotent).
	func start()

	/// Stop monitoring (idempotent). Monitoring can be started again.
	func stop()
}
