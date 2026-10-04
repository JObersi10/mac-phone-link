import XCTest
@testable import ScrcpyProtocol

final class VideoFrameTests: XCTestCase {
    /// Build a 12-byte media packet header (session flag clear).
    private func mediaHeader(config: Bool, key: Bool, pts: UInt64, size: UInt32) -> [UInt8] {
        var word = pts & ((1 << 61) - 1)
        if config { word |= 1 << 62 }
        if key { word |= 1 << 61 }
        return beBytes(word) + beBytes32(size)
    }

    /// Build a 12-byte session packet header (session flag set).
    private func sessionHeader(width: UInt32, height: UInt32) -> [UInt8] {
        let word = (UInt64(1) << 63) | UInt64(width)
        return beBytes(word) + beBytes32(height)
    }

    private func beBytes(_ v: UInt64) -> [UInt8] {
        stride(from: 56, through: 0, by: -8).map { UInt8((v >> UInt64($0)) & 0xff) }
    }
    private func beBytes32(_ v: UInt32) -> [UInt8] {
        stride(from: 24, through: 0, by: -8).map { UInt8((v >> UInt32($0)) & 0xff) }
    }

    func testSessionPacketParsed() throws {
        var demux = VideoDemuxer()
        demux.append(sessionHeader(width: 1080, height: 2400))
        guard case let .session(w, h) = try XCTUnwrap(try demux.next()) else {
            return XCTFail("expected session packet")
        }
        XCTAssertEqual(w, 1080)
        XCTAssertEqual(h, 2400)
    }

    func testMediaPacketAcrossAppends() throws {
        var demux = VideoDemuxer()
        let payload: [UInt8] = [0xAA, 0xBB, 0xCC]
        let header = mediaHeader(config: false, key: true, pts: 123, size: UInt32(payload.count))

        demux.append(Array(header[0..<6]))
        XCTAssertNil(try demux.next())
        demux.append(Array(header[6..<12]) + payload)

        guard case let .media(pkt) = try XCTUnwrap(try demux.next()) else {
            return XCTFail("expected media packet")
        }
        XCTAssertTrue(pkt.isKeyFrame)
        XCTAssertFalse(pkt.isConfig)
        XCTAssertEqual(pkt.pts, 123)
        XCTAssertEqual(pkt.payload, payload)
        XCTAssertNil(try demux.next())
    }

    func testConfigFlag() throws {
        var demux = VideoDemuxer()
        demux.append(mediaHeader(config: true, key: false, pts: 0, size: 2) + [0x01, 0x02])
        guard case let .media(pkt) = try XCTUnwrap(try demux.next()) else {
            return XCTFail("expected media packet")
        }
        XCTAssertTrue(pkt.isConfig)
        XCTAssertFalse(pkt.isKeyFrame)
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
