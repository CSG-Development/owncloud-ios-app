import UIKit
import Combine
import ownCloudSDK
import ownCloudAppShared

private enum Constants {
	static let codeLength: Int = 6
}

final public class DeveloperOptionsViewModel {
	@Published var staticDeviceAddress: String = ""
	@Published var isLoginSettingsEnabled: Bool = false
	private var cancellables = Set<AnyCancellable>()

	private var preferences: HCPreferences {
		HCContext.shared.preferences
	}

	private var deviceReachabilityService: DeviceReachabilityService {
		HCContext.shared.deviceReachabilityService
	}

	private let onClose: (() -> Void)?

	init(onClose: (() -> Void)?) {
		self.onClose = onClose
		staticDeviceAddress = preferences.staticDeviceAddress ?? ""
		isLoginSettingsEnabled = preferences.isLoginSettingsEnabled
	}

	func didTapOk() -> Bool {
		let trimmedAddress = staticDeviceAddress.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmedAddress.isEmpty, !isValidUrlString(trimmedAddress) {
			return false
		}

		preferences.staticDeviceAddress = trimmedAddress.isEmpty ? nil : trimmedAddress
		preferences.isLoginSettingsEnabled = isLoginSettingsEnabled
		onClose?()
		return true
	}

	func didTapCancel() {
		onClose?()
	}

	func didTapOverlay() {
		onClose?()
	}

	private func isValidUrlString(_ string: String) -> Bool {
		let pattern = "^(https?)://((\\d{1,3}\\.){3}\\d{1,3}|([A-Za-z0-9-]+\\.)+[A-Za-z]{2,})(:\\d{1,5})?(/[^\\s]*)?$"
		return string.range(of: pattern, options: .regularExpression) != nil
	}
}
