import Foundation
import Security

public protocol CertificateValidator: AnyObject {
	func validate(trust: SecTrust, host: String) -> Bool
}
