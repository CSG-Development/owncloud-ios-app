import Foundation
import Security

extension CertificateValidationService: CertificateValidator {
	public func validate(trust: SecTrust, host: String) -> Bool {
		evaluate(serverTrust: trust, validateHost: false, host: host)
	}
}
