import XCTest
@testable import ScrcpyProtocol

final class VideoFrameTests: XCTestCase {
    private func header(config: Bool, key: Bool, pts: UInt64, size: UInt32) -> [UInt8] {
        var word = pts
        if config { word |= 1 << 63 }
        if key { word |= 1 << 62 }
        var bytes: [UInt8] = []
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((word >> UInt64(shift)) & 0xff))
        }
        for shift in stride(from: 24, through: 0, by: -8) {
            bytes.append(UInt8((size >> UInt32(shift)) & 0xff))
        }
        return bytes
    }

    func testParseConfigHeader() throws {
        let h = header(config: true, key: false, pts: 0, size: 4)
        let parsed = try parseMediaPacketHeader(h[...])
        XCTAssertTrue(parsed.isConfig)
        XCTAssertFalse(parsed.isKeyFrame)
        XCTAssertEqual(parsed.payloadSize, 4)
    }

    func testDemuxerYieldsCompletePackets() throws {
        var demux = VideoDemuxer()
        let payload: [UInt8] = [0xAA, 0xBB, 0xCC]
        let h = header(config: false, key: true, pts: 123, size: UInt32(payload.count))

        // Feed header and payload split across two appends.
        demux.append(Array(h[0..<6]))
        XCTAssertNil(try demux.next())
        demux.append(Array(h[6..<12]) + payload)

        let pkt = try XCTUnwrap(try demux.next())
        XCTAssertTrue(pkt.isKeyFrame)
        XCTAssertEqual(pkt.pts, 123)
        XCTAssertEqual(pkt.payload, payload)
        XCTAssertNil(try demux.next())
    }

    func testDeviceClipboardParse() {
        var buf: [UInt8] = [0x00] // clipboard tag
        buf += [0, 0, 0, 3]       // length 3
        buf += Array("abc".utf8)
        if case let .message(.clipboard(text), consumed) = parseDeviceMessage(buf) {
            XCTAssertEqual(text, "abc")
            XCTAssertEqual(consumed, 8)
        } else {
            XCTFail("expected clipboard message")
        }
    }
}
