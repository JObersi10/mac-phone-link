// Tests for the video NAL-unit parsing (pure, deterministic). Decode/display
// require a GPU/display surface, so they are not exercised in headless CI.
//
// SPDX-License-Identifier: MIT

import XCTest
import Foundation
@testable import PhoneLinkVideo

final class VideoTests: XCTestCase {
    func testAnnexBSplit4ByteAnd3Byte() {
        // 00000001 [09 10] 000001 [67 20 30]
        let data = Data([0,0,0,1, 0x09,0x10, 0,0,1, 0x67,0x20,0x30])
        let nals = NALParser.annexBToNALUnits(data)
        XCTAssertEqual(nals.count, 2)
        XCTAssertEqual([UInt8](nals[0]), [0x09, 0x10])
        XCTAssertEqual([UInt8](nals[1]), [0x67, 0x20, 0x30])
    }

    func testIsAnnexB() {
        XCTAssertTrue(NALParser.isAnnexB(Data([0,0,0,1,0x67])))
        XCTAssertTrue(NALParser.isAnnexB(Data([0,0,1,0x67])))
        XCTAssertFalse(NALParser.isAnnexB(Data([0,0,0,5,0x67])))
    }

    func testAVCCRoundTrip() {
        let nalA = Data([0x67, 0x01, 0x02])
        let nalB = Data([0x68, 0xAA])
        let avcc = NALParser.toAVCC([nalA, nalB])
        // 4-byte length prefixes: 00000003 67 01 02 00000002 68 AA
        XCTAssertEqual([UInt8](avcc.prefix(4)), [0,0,0,3])
        let back = NALParser.avccToNALUnits(avcc, lengthSize: 4)
        XCTAssertEqual(back, [nalA, nalB])
    }

    func testNalTypeH264AndHEVC() {
        XCTAssertEqual(NALParser.nalType(Data([0x67]), codec: .h264), 7)   // SPS
        XCTAssertEqual(NALParser.nalType(Data([0x68]), codec: .h264), 8)   // PPS
        // HEVC type = (byte>>1)&0x3F ; 0x40 -> 32 (VPS)
        XCTAssertEqual(NALParser.nalType(Data([0x40]), codec: .hevc), 32)
    }

    func testFormatDescriptionRequiresTwoParameterSets() {
        XCTAssertThrowsError(try VideoFormatDescriptionBuilder.make(codec: .h264, parameterSets: [Data([0x67])]))
    }
}
