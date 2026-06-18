import Foundation
import ownCloudSDK

/// Forces active `OCCore` instances offline while the Home Cloud device host is known to be
/// unreachable. Uses an extra `OCCoreConnectionStatusSignalReachable` provider so the SDK
/// stops scheduling online-only work until availability is restored.
public final class SDKDeviceAvailabilityGate: @unchecked Sendable {
	public static let shared = SDKDeviceAvailabilityGate()

	private struct Registration {
		weak var core: OCCore?
		let provider: OCCoreConnectionStatusSignalProvider
	}

	private let lock = NSLock()
	private var registrations: [ObjectIdentifier: Registration] = [:]
	private var forcedOffline = false

	private init() {}

	public func register(core: OCCore) {
		lock.lock()
		defer { lock.unlock() }

		let key = ObjectIdentifier(core)
		guard registrations[key] == nil else { return }

		let provider = OCCoreConnectionStatusSignalProvider(
			signal: .reachable,
			initialState: forcedOffline ? .forceFalse : .true,
			stateProvider: nil
		)
		if forcedOffline {
			provider.shortDescription = HCL10n.Network.connectionLost
		}

		core.addDeviceAvailabilitySignalProvider(provider)
		registrations[key] = Registration(core: core, provider: provider)
	}

	public func setDeviceConnected(_ connected: Bool) {
		lock.lock()
		defer { lock.unlock() }

		let offline = !connected
		guard offline != forcedOffline else { return }
		forcedOffline = offline
		Log.debug("[STX-CONN]: SDK gate→\(connected ? "online" : "offline") (\(registrations.count) core(s))")

		pruneDeadRegistrationsLocked()

		let state: OCCoreConnectionStatusSignalState = offline ? .forceFalse : .true
		for registration in registrations.values {
			registration.provider.shortDescription = offline ? HCL10n.Network.connectionLost : nil
			registration.provider.state = state
		}
	}

	@available(*, deprecated, renamed: "setDeviceConnected")
	public func setDeviceForcedOffline(_ offline: Bool) {
		setDeviceConnected(!offline)
	}

	private func pruneDeadRegistrationsLocked() {
		registrations = registrations.filter { $0.value.core != nil }
	}
}
