// DeviceTrustJWT — builds the signed JWT that populates
// `SideChannelAuthorization.signed_jwt_payload`, i.e. the per-message
// device-to-device trust proof (distinct from the MSA/Entra access token).
//
// Observed shape on the wire: a compact JWS with header {"alg":"RS256","kid":…}
// and claims carrying a server-issued `nonce`, the `dcgClientId`, and a short
// validity window (iat/nbf/exp). Signing uses the device's own RSA key
// (RSASSA-PKCS1-v1_5 / SHA-256).
//
// The signer is abstracted (`JWTSigner`) so the private key can live wherever
// the client keeps it (Keychain, Secure Enclave-wrapped, a test key). A native
// `Security.framework` RSA signer is provided with no extra dependency.
//
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Security)
import Security
#endif
#if canImport(Crypto)
import Crypto
#endif

// MARK: - Signer abstraction

public protocol JWTSigner {
    /// JWS `alg` header value, e.g. "RS256".
    var algorithm: String { get }
    /// JWS `kid` header value (commonly the signing cert thumbprint). May be nil.
    var keyID: String? { get }
    /// Produce a signature over the ASCII signing input (`header.claims`).
    func sign(_ signingInput: Data) throws -> Data
}

public enum DeviceTrustError: Error {
    case jsonEncoding
    case signing(String)
    case keyUnavailable
}

// MARK: - Claims

/// Claims for the device-trust JWT. `issuedAt` defaults to now; `notBefore`
/// and `expiresAt` are derived from `lifetime` unless set explicitly.
public struct DeviceTrustClaims {
    public var dcgClientId: String
    public var nonce: String?
    public var issuer: String?
    public var subject: String?
    public var audience: String?
    public var issuedAt: Date
    public var notBefore: Date?
    public var expiresAt: Date?
    public var jwtID: String?
    /// Any additional claims to merge in verbatim.
    public var additional: [String: String]

    public init(
        dcgClientId: String,
        nonce: String? = nil,
        issuer: String? = nil,
        subject: String? = nil,
        audience: String? = nil,
        issuedAt: Date = Date(),
        lifetime: TimeInterval = 300,
        notBefore: Date? = nil,
        expiresAt: Date? = nil,
        jwtID: String? = nil,
        additional: [String: String] = [:]
    ) {
        self.dcgClientId = dcgClientId
        self.nonce = nonce
        self.issuer = issuer
        self.subject = subject ?? dcgClientId
        self.audience = audience
        self.issuedAt = issuedAt
        self.notBefore = notBefore ?? issuedAt
        self.expiresAt = expiresAt ?? issuedAt.addingTimeInterval(lifetime)
        self.jwtID = jwtID
        self.additional = additional
    }

    func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["dcgClientId"] = dcgClientId
        if let nonce { dict["nonce"] = nonce }
        if let issuer { dict["iss"] = issuer }
        if let subject { dict["sub"] = subject }
        if let audience { dict["aud"] = audience }
        dict["iat"] = Int(issuedAt.timeIntervalSince1970)
        if let notBefore { dict["nbf"] = Int(notBefore.timeIntervalSince1970) }
        if let expiresAt { dict["exp"] = Int(expiresAt.timeIntervalSince1970) }
        if let jwtID { dict["jti"] = jwtID }
        for (k, v) in additional { dict[k] = v }
        return dict
    }
}

// MARK: - Token builder

public enum DeviceTrustJWT {
    /// Assemble and sign a compact JWS (`header.claims.signature`).
    public static func sign(claims: DeviceTrustClaims, with signer: JWTSigner) throws -> String {
        var header: [String: Any] = ["alg": signer.algorithm, "typ": "JWT"]
        if let kid = signer.keyID { header["kid"] = kid }

        let headerSegment = try base64URL(json: header)
        let claimsSegment = try base64URL(json: claims.asDictionary())
        let signingInput = "\(headerSegment).\(claimsSegment)"

        guard let inputData = signingInput.data(using: .ascii) else {
            throw DeviceTrustError.jsonEncoding
        }
        let signature = try signer.sign(inputData)
        return "\(signingInput).\(base64URL(data: signature))"
    }

    // MARK: Encoding helpers

    static func base64URL(json object: [String: Any]) throws -> String {
        // sortedKeys keeps output deterministic (useful for tests / caching).
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { throw DeviceTrustError.jsonEncoding }
        return base64URL(data: data)
    }

    static func base64URL(data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Native RSA (RS256) signer

#if canImport(Security)
/// RS256 signer backed by a `SecKey` RSA private key (Keychain or in-memory).
public struct SecKeyRS256Signer: JWTSigner {
    public let algorithm = "RS256"
    public let keyID: String?
    private let privateKey: SecKey

    public init(privateKey: SecKey, keyID: String? = nil) {
        self.privateKey = privateKey
        self.keyID = keyID
    }

    public func sign(_ signingInput: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData,
            &error
        ) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw DeviceTrustError.signing(message)
        }
        return signature as Data
    }
}
#endif
