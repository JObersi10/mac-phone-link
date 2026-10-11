// Tests for DRS nonce acquisition and cert-thumbprint -> kid derivation,
// including the end-to-end "fetch nonce then authorize" bridge.
//
// SPDX-License-Identifier: MIT

import XCTest
import Foundation
@testable import PhoneLinkProtos
@testable import DCGAuth
@testable import DCGTransport

final class DRSAndThumbprintTests: XCTestCase {

    // MARK: Thumbprint / kid

    // Known vectors for an empty input:
    //   SHA-256("") = e3b0c442...b855 ; SHA-1("") = da39a3ee...0709
    func testThumbprintHexSHA256EmptyVector() {
        let kid = CertThumbprint.kid(certificateDER: Data(), variant: .hexSHA256)
        XCTAssertEqual(kid,
            "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855")
    }

    func testThumbprintHexSHA1EmptyVector() {
        let kid = CertThumbprint.kid(certificateDER: Data(), variant: .hexSHA1)
        XCTAssertEqual(kid, "DA39A3EE5E6B4B0D3255BFEF95601890AFD80709")
    }

    func testThumbprintBase64urlIsUrlSafeAndUnpadded() {
        let kid = CertThumbprint.kid(certificateDER: Data("some-cert-bytes".utf8),
                                     variant: .base64urlSHA256)
        XCTAssertFalse(kid.contains("+"))
        XCTAssertFalse(kid.contains("/"))
        XCTAssertFalse(kid.contains("="))
        // base64url(SHA-256) → 32 bytes → 43 chars unpadded.
        XCTAssertEqual(kid.count, 43)
    }

    // MARK: DRS nonce parsing + URL

    func testNonceURLShape() {
        let client = DRSNonceClient(environment: .production, transport: StubTransport(body: Data()))
        let url = client.nonceURL(tenant: "contoso.onmicrosoft.com")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "enterpriseregistration.windows.net")
        XCTAssertTrue(url?.path.hasSuffix("/EnrollmentServer/device/contoso.onmicrosoft.com") ?? false)
        XCTAssertTrue(url?.query?.contains("nonce=1") ?? false)
    }

    func testParseNonceJSONUpperAndLowerKeys() throws {
        XCTAssertEqual(try DRSNonceClient.parseNonce(from: Data(#"{"Nonce":"abc123"}"#.utf8)), "abc123")
        XCTAssertEqual(try DRSNonceClient.parseNonce(from: Data(#"{"nonce":"xyz"}"#.utf8)), "xyz")
    }

    func testParseNonceBareString() throws {
        XCTAssertEqual(try DRSNonceClient.parseNonce(from: Data("\"raw-nonce\"".utf8)), "raw-nonce")
    }

    func testRequestNonceOverStubTransport() async throws {
        let stub = StubTransport(body: Data(#"{"Nonce":"server-nonce-1"}"#.utf8), status: 200)
        let client = DRSNonceClient(environment: .production, transport: stub)
        let nonce = try await client.requestNonce(tenant: "t.onmicrosoft.com")
        XCTAssertEqual(nonce, "server-nonce-1")
        XCTAssertEqual(stub.lastRequest?.httpMethod, "GET")
    }

    func testRequestNonceHTTPErrorThrows() async {
        let stub = StubTransport(body: Data(), status: 500)
        let client = DRSNonceClient(transport: stub)
        do {
            _ = try await client.requestNonce(tenant: "t")
            XCTFail("expected httpStatus error")
        } catch let error as DRSError {
            guard case .httpStatus(500) = error else { return XCTFail("wrong error: \(error)") }
        } catch { XCTFail("unexpected error type: \(error)") }
    }

    // MARK: End-to-end bridge — fetch nonce then authorize

    func testAuthorizerFetchesNonceAndSigns() async throws {
        struct MockSigner: JWTSigner {
            let algorithm = "RS256"
            let keyID: String? = "kid-1"
            func sign(_ input: Data) throws -> Data { Data("sig".utf8) }
        }
        let stub = StubTransport(body: Data(#"{"Nonce":"drs-nonce-42"}"#.utf8), status: 200)
        let nonceClient = DRSNonceClient(transport: stub)
        let authorizer = DeviceTrustAuthorizer(signer: MockSigner(), dcgClientId: "dcg-xyz")

        let auth = try await authorizer.makeAuthorization(
            fetchingNonceFor: "tenant.onmicrosoft.com", using: nonceClient
        )

        // The signed JWT must carry the nonce DRS returned.
        let parts = auth.signedJwtPayload.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        let claims = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(base64Encoded: b64)!) as? [String: Any]
        )
        XCTAssertEqual(claims["nonce"] as? String, "drs-nonce-42")
        XCTAssertEqual(claims["dcgClientId"] as? String, "dcg-xyz")
    }
}

// MARK: - Stub transport

final class StubTransport: DRSTransport, @unchecked Sendable {
    let body: Data
    let status: Int
    private(set) var lastRequest: URLRequest?

    init(body: Data, status: Int = 200) {
        self.body = body
        self.status = status
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        return (body, response)
    }
}
