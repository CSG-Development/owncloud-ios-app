import Foundation

public enum CertLoadError: Error { case notFound(String), badData(String) }

extension Data {
	/// If data is PEM, decode to DER; if already DER, return as-is.
	public func normalizeToDER() throws -> Data {
		if let s = String(data: self, encoding: .utf8),
		   s.contains("-----BEGIN CERTIFICATE-----") {
			let lines = s
				.replacingOccurrences(of: "\r", with: "")
				.components(separatedBy: "\n")
				.filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") && !$0.isEmpty }
			guard let der = Data(base64Encoded: lines.joined()) else {
				throw CertLoadError.badData("Not a valid X.509")
			}
			return der
		}
		return self
	}
}
