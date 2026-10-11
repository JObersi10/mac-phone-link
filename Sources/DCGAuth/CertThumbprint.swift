// CertThumbprint — derive a JWT `kid` (key identifier) from the device
// signing certificate, mirroring the cert-thumbprint identifiers the trust
// layer uses (withAccountCertificateThumbprint / withPartnerCertificateThumbprint).
//
// The exact hash + encoding the service expects is not fully determinable from
// static analysis, so all common variants are provided and the default is the
// AAD-style base64url SHA-256 (`x5t#S256`). Swap `ThumbprintVariant` if the
// live service rejects it.
//
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

public enum ThumbprintVariant: Sendable {
    /// base64url(SHA-256(DER)) — AAD `x5t#S256` style. Default.
    case base64urlSHA256
    /// base64url(SHA-1(DER)) — AAD `x5t` style.
    case base64urlSHA1
    /// Uppercase hex of SHA-256(DER).
    case hexSHA256
    /// Uppercase hex of SHA-1(DER) — classic Windows cert thumbprint.
    case hexSHA1
}

public enum CertThumbprint {

    /// Compute a `kid` string from a DER-encoded X.509 certificate.
    public static func kid(certificateDER der: Data,
                           variant: ThumbprintVariant = .base64urlSHA256) -> String {
        switch variant {
        case .base64urlSHA256: return base64url(sha256(der))
        case .base64urlSHA1:   return base64url(sha1(der))
        case .hexSHA256:       return hexUpper(sha256(der))
        case .hexSHA1:         return hexUpper(sha1(der))
        }
    }

    #if canImport(Security)
    /// Compute a `kid` from a `SecCertificate` (its DER representation).
    public static func kid(certificate: SecCertificate,
                           variant: ThumbprintVariant = .base64urlSHA256) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return kid(certificateDER: der, variant: variant)
    }
    #endif

    // MARK: Digests

    static func sha256(_ data: Data) -> Data {
        #if canImport(CryptoKit)
        return Data(SHA256.hash(data: data))
        #else
        return data  // unreachable on supported platforms
        #endif
    }

    static func sha1(_ data: Data) -> Data {
        #if canImport(CryptoKit)
        return Data(Insecure.SHA1.hash(data: data))
        #else
        return data
        #endif
    }

    // MARK: Encodings

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hexUpper(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}

#if canImport(Security)
public extension SecKeyRS256Signer {
    /// Build an RS256 signer whose `kid` is derived from the signing certificate.
    init(privateKey: SecKey, certificate: SecCertificate,
         variant: ThumbprintVariant = .base64urlSHA256) {
        self.init(privateKey: privateKey,
                  keyID: CertThumbprint.kid(certificate: certificate, variant: variant))
    }
}
#endif
