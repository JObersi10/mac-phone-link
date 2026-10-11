// Nano transport tests — framing, loopback, context_source handshake.
//
// SPDX-License-Identifier: MIT

import XCTest
import PhoneLinkProtos
@testable import NanoTransport

final class NanoTransportTests: XCTestCase {

    func testEncodeDecodeRoundTrip() throws {
        let payload = Data("hello nano".utf8)
        let framed = try NanoFraming.encode(payload)
        XCTAssertEqual(framed.count, 4 + payload.count)
        var dec = NanoFrameDecoder()
        let frames = try dec.push(framed)
        XCTAssertEqual(frames, [payload])
        XCTAssertEqual(dec.pendingByteCount, 0)
    }

    func testDecoderReassemblesSplitChunks() throws {
        let payload = Data((0..<1000).map { UInt8($0 & 0xff) })
        let framed = try NanoFraming.encode(payload)
        var dec = NanoFrameDecoder()
        // Feed one byte at a time; only the last byte completes the frame.
        var frames: [Data] = []
        for byte in framed {
            frames += try dec.push(Data([byte]))
        }
        XCTAssertEqual(frames, [payload])
    }

    func testDecoderHandlesMultipleFramesInOneChunk() throws {
        let a = Data("one".utf8), b = Data("two".utf8), c = Data("three".utf8)
        var chunk = Data()
        chunk += try NanoFraming.encode(a)
        chunk += try NanoFraming.encode(b)
        chunk += try NanoFraming.encode(c)
        var dec = NanoFrameDecoder()
        XCTAssertEqual(try dec.push(chunk), [a, b, c])
    }

    func testOversizeLengthRejected() {
        // Length prefix of 0xFFFFFFFF with no body → must throw, not allocate.
        var dec = NanoFrameDecoder()
        let bogus = Data([0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertThrowsError(try dec.push(bogus)) { err in
            guard case NanoFraming.Error.frameTooLarge = err else {
                return XCTFail("expected frameTooLarge, got \(err)")
            }
        }
    }

    func testLoopbackDeliversFrames() {
        let t = LoopbackNanoTransport()
        var received: [Data] = []
        t.onFrame = { received.append($0) }
        t.start()
        XCTAssertEqual(t.state, .ready)
        t.send(Data("a".utf8))
        t.send(Data("bb".utf8))
        XCTAssertEqual(received, [Data("a".utf8), Data("bb".utf8)])
    }

    func testHandshakeInitializeAndResponse() throws {
        let hs = NanoHandshake()
        // Initialize round-trips through the wrapper.
        let initMsg = hs.initialize(contextSourceID: "mac-123")
        let initBytes = try hs.serialize(initMsg)
        let parsedInit = try hs.parse(initBytes)
        guard case .csInitializeMessage(let v)? = parsedInit.type else {
            return XCTFail("expected initialize")
        }
        XCTAssertEqual(v.contextSourceID, "mac-123")

        // Identity response echoes the challenge and names the client id.
        var challenge = Maclink_Platform_V1_CSIdentityChallenge()
        challenge.challenge = Data([1, 2, 3, 4])
        let resp = hs.identityResponse(to: challenge, dcgClientID: "client-abc")
        guard case .csIdentityResponse(let r)? = resp.type else {
            return XCTFail("expected response")
        }
        XCTAssertEqual(r.challenge, Data([1, 2, 3, 4]))
        XCTAssertEqual(r.dcgClientID, "client-abc")
    }
}
