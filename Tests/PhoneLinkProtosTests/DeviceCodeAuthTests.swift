// Tests for DeviceCodeAuth wire decoding + ClientIdResolver precedence.
// No network: the resolver is pure, and the challenge decode uses a fixture.
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import DCGAuth

final class DeviceCodeAuthTests: XCTestCase {
    func testClientIdResolverPrecedence() {
        // Explicit beats env beats file.
        XCTAssertEqual(
            ClientIdResolver.resolve(explicit: "  abc  ",
                                     environment: [ClientIdResolver.environmentKey: "env"]),
            "abc")
        XCTAssertEqual(
            ClientIdResolver.resolve(explicit: nil,
                                     environment: [ClientIdResolver.environmentKey: " env-id "]),
            "env-id")
        // Nothing supplied → nil (nothing embedded or assumed).
        XCTAssertNil(ClientIdResolver.resolve(explicit: "   ",
                                              environment: [:],
                                              configURL: URL(fileURLWithPath: "/nonexistent/xyz")))
    }

    func testClientIdResolverReadsConfigFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pl_cid_\(UUID().uuidString)")
        try "file-client-id\nignored second line".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertEqual(
            ClientIdResolver.resolve(explicit: nil, environment: [:], configURL: tmp),
            "file-client-id")
    }

    func testBrokerScopeFormat() {
        let cfg = DeviceCodeConfig(clientId: "CID")
        XCTAssertEqual(cfg.brokerScope("https://dcg.microsoft.com/DCG.ReadWrite"),
                       "https://dcg.microsoft.com/DCG.ReadWrite&api-version=2.0&clientid=CID")
    }

    func testDeviceCodeChallengeDecodes() throws {
        let json = """
        {"device_code":"DC","user_code":"ABCD-EFGH",
         "verification_uri":"https://microsoft.com/link","expires_in":900,
         "interval":5,"message":"go to the link"}
        """.data(using: .utf8)!
        let c = try JSONDecoder().decode(DeviceCodeChallenge.self, from: json)
        XCTAssertEqual(c.userCode, "ABCD-EFGH")
        XCTAssertEqual(c.interval, 5)
        XCTAssertEqual(c.verificationURI.absoluteString, "https://microsoft.com/link")
    }

    func testDefaultAuthorityIsConsumers() {
        let cfg = DeviceCodeConfig(clientId: "x")
        XCTAssertTrue(cfg.authority.absoluteString.hasSuffix("/consumers"))
        XCTAssertEqual(cfg.deviceCodeEndpoint.lastPathComponent, "devicecode")
        XCTAssertEqual(cfg.tokenEndpoint.lastPathComponent, "token")
    }
}
