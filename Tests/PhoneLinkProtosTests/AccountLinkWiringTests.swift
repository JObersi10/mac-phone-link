// Tests the DCGFeatureTransport envelope bridge: outbound sends get wrapped in a
// YPPEnvelope and written to the channel; inbound channel frames get unwrapped
// and routed by handler type. Uses a fake in-memory DCGChannel (no network).
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import PhoneLinkUI
@testable import DCGTransport

private final class FakeDCGChannel: DCGChannel {
    var onReceive: ((Data) -> Void)?
    var onStateChange: ((DCGChannelState) -> Void)?
    var sent: [Data] = []
    var started = false
    func start() { started = true }
    func stop() { started = false }
    func send(_ frame: Data, completion: @escaping (Error?) -> Void) {
        sent.append(frame); completion(nil)
    }
    /// Simulate a server→client frame.
    func inject(_ frame: Data) { onReceive?(frame) }
}

final class AccountLinkWiringTests: XCTestCase {
    func testOutboundWrapsInEnvelope() throws {
        let ch = FakeDCGChannel()
        let transport = DCGFeatureTransport(channel: ch)
        transport.send(handlerType: "clipboard", Data("copied".utf8))
        XCTAssertEqual(ch.sent.count, 1)
        let env = try YPPEnvelope(decodingJSON: ch.sent[0])
        XCTAssertEqual(env.route, "clipboard")
        XCTAssertEqual(env.payload, Data("copied".utf8))
    }

    func testInboundRoutesByHandlerType() throws {
        let ch = FakeDCGChannel()
        let transport = DCGFeatureTransport(channel: ch)
        var got: (String, Data)?
        transport.onPayload = { got = ($0, $1) }
        let wire = try YPPEnvelope(route: "notifications",
                                   contentType: "application/octet-stream",
                                   payload: Data("ping".utf8)).encodedJSON()
        ch.inject(wire)
        XCTAssertEqual(got?.0, "notifications")
        XCTAssertEqual(got?.1, Data("ping".utf8))
    }

    func testStartStopForwards() {
        let ch = FakeDCGChannel()
        let transport = DCGFeatureTransport(channel: ch)
        transport.start(); XCTAssertTrue(ch.started)
        transport.stop(); XCTAssertFalse(ch.started)
    }
}
