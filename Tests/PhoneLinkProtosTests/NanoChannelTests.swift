// Pins the confirmed Nano channel model (docs/FINDINGS.md § "Nano transport").
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import NanoTransport

final class NanoChannelTests: XCTestCase {

    func testChannelTypesMatchLibNanoApi() {
        // The five typed channels LibNanoAPI multiplexes over one Connect.
        let kinds = Set(NanoChannelType.allCases)
        XCTAssertEqual(kinds, [.videoTarget, .audioTarget, .inputSource, .message, .blob])
    }

    func testConnectRoles() {
        XCTAssertEqual(NanoConnectRole.client.rawValue, "client")
        XCTAssertEqual(NanoConnectRole.server.rawValue, "server")
    }

    func testChannelIdentity() {
        let a = NanoChannel(id: 7, type: .videoTarget)
        let b = NanoChannel(id: 7, type: .videoTarget)
        let c = NanoChannel(id: 8, type: .videoTarget)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
