// Tests for DRS discovery metadata parsing and the unified DCGSession wiring.
//
// SPDX-License-Identifier: MIT

import XCTest
import Foundation
@testable import PhoneLinkProtos
@testable import DCGAuth
@testable import DCGTransport

final class DCGSessionTests: XCTestCase {

    struct MockSigner: JWTSigner {
        let algorithm = "RS256"
        let keyID: String? = "kid"
        func sign(_ input: Data) throws -> Data { Data("s".utf8) }
    }

    // MARK: DRS discovery

    func testDiscoveryURLShape() {
        let client = DRSDiscoveryClient(transport: StubTransport(body: Data()))
        let url = client.discoveryURL(tenant: "contoso.onmicrosoft.com")
        XCTAssertEqual(url?.host, "enterpriseregistration.windows.net")
        XCTAssertTrue(url?.path.hasSuffix("/contoso.onmicrosoft.com/EnrollmentServer/contract") ?? false)
        XCTAssertTrue(url?.query?.contains("api-version=1.0") ?? false)
    }

    func testDiscoveryParsesRegistrationEndpointAndBuildsNonceURL() async throws {
        let json = """
        {
          "DeviceRegistrationService": {
            "RegistrationEndpoint": "https://enterpriseregistration.windows.net/contoso/EnrollmentServer/device/?api-version=1.0"
          }
        }
        """
        let client = DRSDiscoveryClient(transport: StubTransport(body: Data(json.utf8)))
        let metadata = try await client.discover(tenant: "contoso")
        XCTAssertNotNil(metadata.registrationEndpoint)

        let nonceURL = try XCTUnwrap(metadata.nonceURL())
        XCTAssertTrue(nonceURL.absoluteString.contains("nonce=1"))
        XCTAssertTrue(nonceURL.absoluteString.contains("api-version=1.0"))
    }

    func testRequestNonceViaDiscovery() async throws {
        // Two-hop: discovery returns metadata, nonce request returns the nonce.
        let discoBody = Data("""
        {"DeviceRegistrationService":{"RegistrationEndpoint":"https://enterpriseregistration.windows.net/t/EnrollmentServer/device/"}}
        """.utf8)
        let discovery = DRSDiscoveryClient(transport: StubTransport(body: discoBody))
        let nonceClient = DRSNonceClient(transport: StubTransport(body: Data(#"{"Nonce":"disc-nonce"}"#.utf8)))
        let nonce = try await nonceClient.requestNonce(discoveringFor: "t", discovery: discovery)
        XCTAssertEqual(nonce, "disc-nonce")
    }

    // MARK: DCGSession wiring

    func testSessionStartUsesTokenAndOpensConnection() async throws {
        let mockChannel = MockChannel()
        var tokenCalls = 0
        let authorizer = DeviceTrustAuthorizer(signer: MockSigner(), dcgClientId: "dcg")
        let session = DCGSession(
            config: DCGSessionConfig(hubURL: URL(string: "https://dcg.microsoft.com/hub")!,
                                     tenant: "t", sessionID: "sess-1"),
            accessTokenProvider: { tokenCalls += 1; return "msa-token-\(tokenCalls)" },
            deviceTrust: authorizer,
            channelFactory: { _ in mockChannel }
        )

        let conn = try await session.start()
        XCTAssertEqual(tokenCalls, 1)
        XCTAssertNotNil(session.connection)

        // The connection fragments and writes onto the injected channel.
        try conn.send(payload: Data([1, 2, 3]), handlerType: "clipboard")
        XCTAssertEqual(mockChannel.sent.count, 1)
    }

    func testSessionCurrentAuthorizationBindsDiscoveredNonce() async throws {
        let discoBody = Data("""
        {"DeviceRegistrationService":{"RegistrationEndpoint":"https://enterpriseregistration.windows.net/t/EnrollmentServer/device/"}}
        """.utf8)
        let session = DCGSession(
            config: DCGSessionConfig(hubURL: URL(string: "https://dcg.microsoft.com/hub")!, tenant: "t"),
            accessTokenProvider: { "tok" },
            deviceTrust: DeviceTrustAuthorizer(signer: MockSigner(), dcgClientId: "dcg-7"),
            nonceClient: DRSNonceClient(transport: StubTransport(body: Data(#"{"Nonce":"n-77"}"#.utf8))),
            discovery: DRSDiscoveryClient(transport: StubTransport(body: discoBody)),
            channelFactory: { _ in MockChannel() }
        )
        let auth = try await session.currentAuthorization()

        var b64 = String(auth.signedJwtPayload.split(separator: ".")[1])
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        let claims = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(base64Encoded: b64)!) as? [String: Any]
        )
        XCTAssertEqual(claims["nonce"] as? String, "n-77")
        XCTAssertEqual(claims["dcgClientId"] as? String, "dcg-7")
    }
}
