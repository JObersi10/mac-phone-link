// Tests for the device-trust JWT signing module and its bridge to
// SideChannelAuthorization.
//
// SPDX-License-Identifier: MIT

import XCTest
import Foundation
@testable import PhoneLinkProtos
@testable import DCGAuth
@testable import DCGTransport
#if canImport(Security)
import Security
#endif

final class DeviceTrustTests: XCTestCase {

    /// Deterministic signer for structural assertions (no real crypto).
    struct MockSigner: JWTSigner {
        let algorithm = "RS256"
        let keyID: String? = "test-kid"
        func sign(_ signingInput: Data) throws -> Data { Data("signature".utf8) }
    }

    private func decodeSegment(_ segment: Substring) -> [String: Any]? {
        var b64 = String(segment)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func testCompactStructureAndHeader() throws {
        let claims = DeviceTrustClaims(dcgClientId: "dcg-123", nonce: "n-abc")
        let jwt = try DeviceTrustJWT.sign(claims: claims, with: MockSigner())

        let parts = jwt.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "compact JWS must have 3 segments")

        let header = decodeSegment(parts[0])
        XCTAssertEqual(header?["alg"] as? String, "RS256")
        XCTAssertEqual(header?["typ"] as? String, "JWT")
        XCTAssertEqual(header?["kid"] as? String, "test-kid")
    }

    func testClaimsEncoding() throws {
        let iat = Date(timeIntervalSince1970: 1_700_000_000)
        let claims = DeviceTrustClaims(
            dcgClientId: "dcg-123",
            nonce: "nonce-xyz",
            issuer: "device-xyz",
            audience: "dcg.microsoft.com",
            issuedAt: iat,
            lifetime: 300
        )
        let jwt = try DeviceTrustJWT.sign(claims: claims, with: MockSigner())
        let payload = decodeSegment(jwt.split(separator: ".")[1])

        XCTAssertEqual(payload?["dcgClientId"] as? String, "dcg-123")
        XCTAssertEqual(payload?["nonce"] as? String, "nonce-xyz")
        XCTAssertEqual(payload?["iss"] as? String, "device-xyz")
        XCTAssertEqual(payload?["sub"] as? String, "dcg-123")       // defaults to client id
        XCTAssertEqual(payload?["aud"] as? String, "dcg.microsoft.com")
        XCTAssertEqual(payload?["iat"] as? Int, 1_700_000_000)
        XCTAssertEqual(payload?["nbf"] as? Int, 1_700_000_000)
        XCTAssertEqual(payload?["exp"] as? Int, 1_700_000_300)
    }

    func testSigningInputIsStableAndSigned() throws {
        // The mock signs "signature"; verify the 3rd segment is its base64url.
        let claims = DeviceTrustClaims(dcgClientId: "c", issuedAt: Date(timeIntervalSince1970: 1))
        let jwt = try DeviceTrustJWT.sign(claims: claims, with: MockSigner())
        let sigSegment = String(jwt.split(separator: ".")[2])
        let expected = DeviceTrustJWT.base64URL(data: Data("signature".utf8))
        XCTAssertEqual(sigSegment, expected)
    }

    func testBridgeProducesSideChannelAuthorization() throws {
        let authorizer = DeviceTrustAuthorizer(
            signer: MockSigner(),
            dcgClientId: "dcg-999",
            issuer: "device-1"
        )
        let auth = try authorizer.makeAuthorization(nonce: "server-nonce")
        XCTAssertFalse(auth.signedJwtPayload.isEmpty)
        XCTAssertEqual(auth.signedJwtPayload.split(separator: ".").count, 3)

        // It round-trips through the protobuf and carries the nonce we signed.
        let data = try auth.serializedData()
        let parsed = try Maclink_Sidechannel_V1_Authorization(serializedBytes: data)
        let payload = decodeSegment(parsed.signedJwtPayload.split(separator: ".")[1])
        XCTAssertEqual(payload?["nonce"] as? String, "server-nonce")
        XCTAssertEqual(payload?["dcgClientId"] as? String, "dcg-999")
    }

    func testAuthorizerStampsClientRequest() throws {
        let authorizer = DeviceTrustAuthorizer(signer: MockSigner(), dcgClientId: "dcg-1")
        var req = Maclink_Sidechannel_V1_ClientRequest()
        req.wakeRequest = Maclink_Sidechannel_V1_WakeRequest()
        try authorizer.authorize(&req, nonce: "n1")
        XCTAssertFalse(req.authorization.signedJwtPayload.isEmpty)

        let roundTripped = try Maclink_Sidechannel_V1_ClientRequest(serializedBytes: req.serializedData())
        XCTAssertFalse(roundTripped.authorization.signedJwtPayload.isEmpty)
    }

    #if canImport(Security) && os(macOS)
    func testSecKeyRS256SignVerify() throws {
        // Generate an in-memory RSA key, sign a JWT, and verify the signature
        // against the public key with the same algorithm.
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw XCTSkip("RSA key generation unavailable: \(String(describing: error?.takeRetainedValue()))")
        }
        guard let pub = SecKeyCopyPublicKey(priv) else { return XCTFail("no public key") }

        let signer = SecKeyRS256Signer(privateKey: priv, keyID: "unit")
        let jwt = try DeviceTrustJWT.sign(
            claims: DeviceTrustClaims(dcgClientId: "dcg-sec", nonce: "n"),
            with: signer
        )
        let parts = jwt.split(separator: ".")
        let signingInput = "\(parts[0]).\(parts[1])".data(using: .ascii)!

        var sigB64 = String(parts[2]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while sigB64.count % 4 != 0 { sigB64.append("=") }
        let signature = Data(base64Encoded: sigB64)!

        let ok = SecKeyVerifySignature(
            pub, .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData, signature as CFData, &error
        )
        XCTAssertTrue(ok, "RS256 signature should verify against the public key")
    }
    #endif
}
