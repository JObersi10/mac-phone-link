// Tests for LANTransport's length-prefix framing (pure logic).
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import LANTransport

final class LANFramerTests: XCTestCase {
    func testFrameRoundTrip() {
        var framer = LengthPrefixFramer()
        let a = Data("hello".utf8), b = Data("world!".utf8)
        let wire = LengthPrefixFramer.frame(a) + LengthPrefixFramer.frame(b)
        XCTAssertEqual(framer.push(wire), [a, b])
    }

    func testPartialThenComplete() {
        var framer = LengthPrefixFramer()
        let msg = Data("fragmented".utf8)
        let wire = LengthPrefixFramer.frame(msg)
        // Deliver one byte at a time; only the final byte completes the message.
        var out: [Data] = []
        for i in wire.indices { out += framer.push(wire.subdata(in: i..<(i+1))) }
        XCTAssertEqual(out, [msg])
    }

    func testTwoMessagesAcrossChunkBoundary() {
        var framer = LengthPrefixFramer()
        let a = Data(repeating: 0xAB, count: 300), b = Data("x".utf8)
        let wire = LengthPrefixFramer.frame(a) + LengthPrefixFramer.frame(b)
        let mid = wire.count / 3
        var out = framer.push(wire.subdata(in: 0..<mid))
        out += framer.push(wire.subdata(in: mid..<wire.count))
        XCTAssertEqual(out, [a, b])
    }

    func testEmptyPayload() {
        var framer = LengthPrefixFramer()
        XCTAssertEqual(framer.push(LengthPrefixFramer.frame(Data())), [Data()])
    }
}
