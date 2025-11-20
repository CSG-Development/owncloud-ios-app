import Foundation
import Network
import Combine

public final class DefaultReachabilityObserver: ReachabilityObserving {
	private let monitorQueue = DispatchQueue(label: "reachability.monitor.queue")
	private let monitor = NWPathMonitor()
	private var isMonitoring: Bool = false
	private let subject: CurrentValueSubject<NetworkState, Never>

	public init() {
		let initial = NetworkState(
			status: .requiresConnection,
			isReachable: false,
			isExpensive: false,
			interface: .none
		)
		self.subject = CurrentValueSubject(initial)
	}

	public var updatesPublisher: AnyPublisher<NetworkState, Never> { subject.eraseToAnyPublisher() }

	public var currentState: NetworkState { subject.value }

	public func start() { _startIfNeeded() }

	public func stop() { _stopIfNeeded() }

	private func _startIfNeeded() {
		guard !isMonitoring else { return }

		isMonitoring = true

		monitor.pathUpdateHandler = { [weak self] path in
			self?.handlePathUpdate(path)
		}
		monitor.start(queue: monitorQueue)
	}

	private func _stopIfNeeded() {
		guard isMonitoring else { return }

		isMonitoring = false

		monitor.cancel()
	}

	private func handlePathUpdate(_ path: NWPath) {
		let status = path.status
		let reachable = (status == .satisfied)
		let expensive = path.isExpensive

		let iface: NetworkState.Interface =
			path.usesInterfaceType(.wifi) ? .wifi :
			path.usesInterfaceType(.cellular) ? .cellular :
			path.usesInterfaceType(.wiredEthernet) ? .wired :
			(reachable ? .other : .none)

		let newState = NetworkState(
			status: status,
			isReachable: reachable,
			isExpensive: expensive,
			interface: iface
		)

		subject.send(newState)
	}
}
