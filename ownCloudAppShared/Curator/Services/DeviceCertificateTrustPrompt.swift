import Foundation
import ownCloudSDK
import UIKit

enum DeviceCertificateTrustPrompt {
	static func askToTrust(
		host: String?,
		certificate: OCCertificate,
		completion: @escaping (Bool) -> Void
	) {
		let title = HCL10n.TrustPrompt.title
		let hostPart = host ?? certificate.hostName ?? certificate.commonName ?? "?"
		let message = String(
			format: HCL10n.TrustPrompt.messageFormat,
			hostPart
		)

		OnMainThread {
			guard let presenter = UserInterfaceContext.shared.currentViewControllerForPresenting else {
				completion(false)
				return
			}

			let alert = ThemedAlertController(
				title: title,
				message: message,
				preferredStyle: .alert
			)

			alert.addAction(
				UIAlertAction(
					title: HCL10n.Common.cancel,
					style: .cancel,
					handler: { _ in completion(false) }
				)
			)

			alert.addAction(
				UIAlertAction(
					title: HCL10n.TrustPrompt.trust,
					style: .default,
					handler: { _ in
						if let der = certificate.certificateData {
							HCPreferences.shared.addTrustedDeviceCertificate(der)
							CertificateValidationService.shared.reloadAnchors()
						}
						completion(true)
					}
				)
			)

			presenter.present(alert, animated: true, completion: nil)
		}
	}
}
