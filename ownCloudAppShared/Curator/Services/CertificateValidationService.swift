import Foundation
import Security
import ownCloudSDK
import X509
import SwiftASN1
import Crypto

public final class CertificateValidationService {
	static let shared = CertificateValidationService()
	private var anchors: [Certificate] = []

	private init() {
		reloadAnchors()
	}

	public func reloadAnchors() {
		anchors = loadPinnedCertificates(
			from: HCConfig.devicePinnedCertificateFiles,
			includingUserTrusted: true
		)
	}

	public func validatePinnedCertificate(
		serverCertificate: OCCertificate,
		host: String?,
		validateHost: Bool
	) -> Bool {
		if HCConfig.disableCertificatePinning {
			return true
		}
		guard let trustRef = serverCertificate.trustRef()?.takeUnretainedValue() else {
			return false
		}

		return evaluate(
			serverTrust: trustRef,
			pinnedCertificates: anchors,
			validateHost: validateHost,
			host: host
		)
	}

	public func evaluate(
		serverTrust: SecTrust,
		validateHost: Bool,
		host: String?
	) -> Bool {
		if HCConfig.disableCertificatePinning {
			return true
		}
		guard anchors.isEmpty == false else {
			return false
		}

		return evaluate(
			serverTrust: serverTrust,
			pinnedCertificates: anchors,
			validateHost: validateHost,
			host: host
		)
	}

	private func evaluate(
		serverTrust: SecTrust,
		pinnedCertificates: [Certificate],
		validateHost: Bool,
		host: String?
	) -> Bool {
		guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
			  let leaf = chain.first
		else {
			return false
		}

		// For the user trusted ones.
		if isKnownServerCertificate(leaf) {
			return true
		}

// Ignore for now.
//		if systemTrustPasses(
//			serverTrust: serverTrust,
//			validateHost: validateHost,
//			host: host
//		) {
//			return true
//		}

		let x509Chain = chain.compactMap { try? Certificate($0) }
		// For the pins.
		if localPinnedTrustPasses(
			chain: x509Chain,
			pinnedAnchors: pinnedCertificates
		) {
			return true
		}

		return false
	}

	private func systemTrustPasses(
		serverTrust: SecTrust,
		validateHost: Bool,
		host: String?
	) -> Bool {
		let policy = SecPolicyCreateSSL(validateHost, validateHost ? host as CFString? : nil)
		SecTrustSetPolicies(serverTrust, policy)
		SecTrustSetNetworkFetchAllowed(serverTrust, true)

		var error: CFError?
		let ok = SecTrustEvaluateWithError(serverTrust, &error)
		if !ok, let error {
			print("System trust failed: \(error)")
		}
		return ok
	}

	private func localPinnedTrustPasses(
		chain: [Certificate],
		pinnedAnchors: [Certificate]
	) -> Bool {
		guard !pinnedAnchors.isEmpty, !chain.isEmpty else {
			return false
		}

		// TODO: Add chain trust cache to avoid full trust reevaluation for every request.

		let x509Chain: [Certificate] = chain
		let x509Anchors: [Certificate] = pinnedAnchors
		guard x509Chain.count == chain.count, x509Anchors.isEmpty == false else {
			print("Failed to parse certificates into X509 format for manual validation")

			return false
		}

		for anchor in x509Anchors {
			if self.validateCertificateChain(chainCertificates: x509Chain, anchorCertificate: anchor) {
				return true
			}
		}

		return false
	}

	private func validateCertificateChain(
		chainCertificates: [Certificate],
		anchorCertificate: Certificate,
		validationDate: Date = Date()
	) -> Bool {
		guard !chainCertificates.isEmpty else {
			return false
		}
		var chainCertificates = chainCertificates
		// The last certificate must match the pinned root. If it is not the case add the root.
		if let chainRoot = chainCertificates.last, chainRoot.subject.description != anchorCertificate.subject.description {
			chainCertificates.append(anchorCertificate)
		}

		// Walk the chain: child -> issuer
		for i in 0..<(chainCertificates.count - 1) {
			let child = chainCertificates[i]
			let issuer = chainCertificates[i + 1]

			// Issuer DN must match subject DN
			guard child.issuer.description == issuer.subject.description else {
				return false
			}

			// Validity period check (child)
			guard child.notValidBefore <= validationDate,
				  validationDate <= child.notValidAfter
			else {
				return false
			}

			// Cryptographic signature verification
			guard issuer.publicKey.isValidSignature(
				child.signature,
				for: child
			) else {
				return false
			}
			let anchorFingerprint = fingerprint(for: anchorCertificate)

			let childMatchAnchor = anchorFingerprint == fingerprint(for: child)
			let issuerMatchAnchor = anchorFingerprint == fingerprint(for: issuer)

			// We reached pinned cert. Do not verify further.
			if childMatchAnchor || issuerMatchAnchor {
				return true
			}
		}

		return true
	}
}

extension CertificateValidationService {
	private func loadPinnedCertificates(
		from bases: [String],
		includingUserTrusted: Bool = false
	) -> [Certificate] {
		var result: [Certificate] = []

		for base in bases {
			guard let url = Bundle.sharedAppBundle.url(forResource: base, withExtension: nil) else {
				continue
			}
			do {
				let data = try Data(contentsOf: url)
				let der = try data.normalizeToDER()
				if let secCert = SecCertificateCreateWithData(nil, der as CFData), let cert = try? Certificate(secCert) {
					result.append(cert)
				}
			} catch {
				continue
			}
		}

		if includingUserTrusted {
			let certs = HCPreferences.shared.trustedDeviceCertificates
			for der in certs {
				if let secCert = SecCertificateCreateWithData(nil, der as CFData), let cert = try? Certificate(secCert) {
					result.append(cert)
				}
			}
		}
		return result
	}

	private func isKnownServerCertificate(_ certificate: SecCertificate) -> Bool {
		let der = SecCertificateCopyData(certificate) as Data
		let known = HCPreferences.shared.trustedDeviceCertificates
		return known.contains(der)
	}

	private func fingerprint(for certificate: Certificate) -> String? {
		guard let data = certificateFingerprintSHA256(certificate) else {
			return nil
		}
		return hexString(data)
	}

	private func certificateFingerprintSHA256(_ certificate: Certificate) -> Data? {
		do {
			var serializer = DER.Serializer()
			try certificate.serialize(into: &serializer)
			let derBytes = Data(serializer.serializedBytes)
			let digest = SHA256.hash(data: derBytes)
			return Data(digest)
		} catch {
			return nil
		}
	}

	private func hexString(_ data: Data) -> String {
		data.map { String(format: "%02X", $0) }.joined(separator: ":")
	}
}
