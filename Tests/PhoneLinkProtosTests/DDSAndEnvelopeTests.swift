// Tests for the DDS device record + YPP feature envelope (steps 2 & 3).
// Pure/no-network: Codable round-trips and envelope field preservation.
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import DCGTransport

final class DDSAndEnvelopeTests: XCTestCase {
    func testDeviceRegistrationRoundTrips() throws {
        let d = DeviceRegistration(selfClientId: "self-1", displayName: "My Mac",
                                   publicCertificate: "QkFTRTY0", trustType: "AccountPairingD2D",
                                   capabilities: ["clipboard", "notifications"])
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(DeviceRegistration.self, from: data)
        XCTAssertEqual(d, back)
        XCTAssertEqual(back.platform, "macOS")
        XCTAssertEqual(back.trustType, "AccountPairingD2D")
    }

    func testEnvelopeJSONRoundTrip() throws {
        let payload = Data("hello feature".utf8)
        let env = YPPEnvelope(route: "clipboard/set", contentType: "application/x-protobuf",
                              payload: payload, remoteAppId: "com.peer.app")
        let json = try env.encodedJSON()
        // Field names must match the documented wire shape.
        let s = String(decoding: json, as: UTF8.self)
        XCTAssertTrue(s.contains("\"_requestId\""))
        XCTAssertTrue(s.contains("\"_route\""))
        XCTAssertTrue(s.contains("\"remoteAppId\""))
        let back = try YPPEnvelope(decodingJSON: json)
        XCTAssertEqual(back.route, "clipboard/set")
        XCTAssertEqual(back.payload, payload)
        XCTAssertEqual(back.remoteAppId, "com.peer.app")
        XCTAssertEqual(back.requestId, env.requestId)
        XCTAssertFalse(back.gzip)
    }

    func testEnvelopeRejectsBadBase64() {
        let bad = Data(#"{"_requestId":"r","_route":"x","contentType":"c","remoteAppId":null,"gzip":false,"payload":"!!!notb64!!!"}"#.utf8)
        XCTAssertThrowsError(try YPPEnvelope(decodingJSON: bad))
    }
}
