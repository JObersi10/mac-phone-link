// RemoteControl + ClipboardCodec tests.
//
// SPDX-License-Identifier: MIT

import XCTest
import CoreGraphics
import PhoneLinkProtos
@testable import PhoneLinkUI

final class RemoteControlTests: XCTestCase {

    // A 1000x1000 view showing a 1080x2400 (portrait) video: aspect-fit leaves
    // horizontal letterbox bars; content is 450 wide, centered.
    private let viewSize = CGSize(width: 1000, height: 1000)
    private let videoSize = CGSize(width: 1080, height: 2400)

    func testContentRectIsLetterboxed() {
        let r = RemoteControl.videoContentRect(viewSize: viewSize, videoSize: videoSize)
        XCTAssertEqual(r.height, 1000, accuracy: 0.5)      // fills vertically
        XCTAssertEqual(r.width, 450, accuracy: 0.5)        // 1080/2400 * 1000
        XCTAssertEqual(r.midX, 500, accuracy: 0.5)         // centered
    }

    func testCenterMapsToHalfHalf() {
        let n = RemoteControl.normalize(viewPoint: CGPoint(x: 500, y: 500),
                                        viewSize: viewSize, videoSize: videoSize)
        XCTAssertNotNil(n)
        XCTAssertEqual(n!.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(n!.y, 0.5, accuracy: 0.001)
    }

    func testPointInLetterboxBarIsRejected() {
        // x=100 is inside the left black bar (content starts at ~275).
        XCTAssertNil(RemoteControl.normalize(viewPoint: CGPoint(x: 100, y: 500),
                                             viewSize: viewSize, videoSize: videoSize))
    }

    func testCornersClampWithinUnitSquare() {
        let r = RemoteControl.videoContentRect(viewSize: viewSize, videoSize: videoSize)
        let tl = RemoteControl.normalize(viewPoint: CGPoint(x: r.minX + 0.1, y: r.minY + 0.1),
                                         viewSize: viewSize, videoSize: videoSize)
        XCTAssertNotNil(tl)
        XCTAssertGreaterThanOrEqual(tl!.x, 0); XCTAssertLessThanOrEqual(tl!.x, 1)
        XCTAssertGreaterThanOrEqual(tl!.y, 0); XCTAssertLessThanOrEqual(tl!.y, 1)
    }

    func testMoveCoalescerSuppressesTinyMoves() {
        var c = MoveCoalescer(minDelta: 0.01)
        XCTAssertTrue(c.shouldSend(CGPoint(x: 0.5, y: 0.5)))     // first always sends
        XCTAssertFalse(c.shouldSend(CGPoint(x: 0.502, y: 0.5)))  // below threshold
        XCTAssertTrue(c.shouldSend(CGPoint(x: 0.52, y: 0.5)))    // above threshold
    }

    func testPointerEventCarriesNormalizedCoords() {
        let e = RemoteControl.pointer(.pointerDown, at: CGPoint(x: 0.25, y: 0.75), button: 1)
        XCTAssertEqual(e.kind, .pointerDown)
        XCTAssertEqual(e.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(e.y, 0.75, accuracy: 0.0001)
        XCTAssertEqual(e.button, 1)
    }

    func testClipboardTextRoundTrip() {
        let msg = ClipboardCodec.response([ClipboardCodec.textItem("hello 📋")])
        let data = try! msg.serializedData()
        let parsed = try! Maclink_Clipboard_V1_ResponseMessage(serializedBytes: data)
        XCTAssertEqual(ClipboardCodec.firstText(in: parsed), "hello 📋")
        XCTAssertEqual(parsed.status, .ok)
    }
}
