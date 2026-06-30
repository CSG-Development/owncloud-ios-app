import Foundation

public enum HCConfig {
	public static let resetPasswordLink = URL(string: "https://seagate.com/")!
	public static let supportLink: URL = URL(string: "http://seagate.com/")!

	// Pinning
    public static var disableCertificatePinning: Bool = false
	public static let raPinnedCertificateFiles: [String] = [
		"fake-device-noveo.cer"
	]
	public static let devicePinnedCertificateFiles: [String] = [
		"_.remote.lasea.fr.pem",
		"tdci.pem",
		"_.noveogroup.com.pem",
		"ca.crt"
	]
}
