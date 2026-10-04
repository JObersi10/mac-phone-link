import XCTest
@testable import ScrcpyProtocol

final class ControlMessageTests: XCTestCase {
    func testInjectKeycodeLayout() {
        let msg = ControlMessage.injectKeycode(action: .down, keycode: 0x42,
                                               repeatCount: 0, metaState: 0)
        let bytes = msg.serialize()
        // type(1) + action(1) + keycode(4) + repeat(4) + metastate(4) = 14
        XCTAssertEqual(bytes.count, 14)
        XCTAssertEqual(bytes[0], ControlMessageType.injectKeycode.rawValue)
        XCTAssertEqual(bytes[1], KeyAction.down.rawValue)
        XCTAssertEqual(Array(bytes[2..<6]), [0, 0, 0, 0x42]) // big-endian keycode
    }

    func testInjectTouchLayout() {
        let pos = ScreenPosition(x: 100, y: 200, screenWidth: 1080, screenHeight: 2400)
        let msg = ControlMessage.injectTouch(action: .down, pointerId: 0xFFFF_FFFF_FFFF_FFFF,
                                             position: pos, pressure: 1.0,
                                             actionButton: 1, buttons: 1)
        let bytes = msg.serialize()
        // type(1)+action(1)+pointerId(8)+position(12)+pressure(2)+actionButton(4)+buttons(4) = 32
        XCTAssertEqual(bytes.count, 32)
        XCTAssertEqual(bytes[0], ControlMessageType.injectTouchEvent.rawValue)
        XCTAssertEqual(Array(bytes[2..<10]), Array(repeating: 0xFF, count: 8))
        // pressure 1.0 -> 0xffff
        XCTAssertEqual(Array(bytes[22..<24]), [0xFF, 0xFF])
    }

    func testInjectScrollLayout() {
        let pos = ScreenPosition(x: 0, y: 0, screenWidth: 1080, screenHeight: 2400)
        let msg = ControlMessage.injectScroll(position: pos, hScroll: 1.0, vScroll: -1.0, buttons: 0)
        let bytes = msg.serialize()
        // type(1)+position(12)+hscroll(2)+vscroll(2)+buttons(4) = 21
        XCTAssertEqual(bytes.count, 21)
        XCTAssertEqual(bytes[0], ControlMessageType.injectScrollEvent.rawValue)
        // hscroll 1.0 -> 0x7fff ; vscroll -1.0 -> 0x8000
        XCTAssertEqual(Array(bytes[13..<15]), [0x7F, 0xFF])
        XCTAssertEqual(Array(bytes[15..<17]), [0x80, 0x00])
    }

    func testSetClipboardLayout() {
        let msg = ControlMessage.setClipboard(sequence: 1, paste: true, text: "hi")
        let bytes = msg.serialize()
        // type(1)+sequence(8)+paste(1)+len(4)+text(2) = 16
        XCTAssertEqual(bytes.count, 16)
        XCTAssertEqual(bytes[0], ControlMessageType.setClipboard.rawValue)
        XCTAssertEqual(bytes[9], 1) // paste flag
        XCTAssertEqual(Array(bytes[10..<14]), [0, 0, 0, 2]) // length
        XCTAssertEqual(Array(bytes[14..<16]), Array("hi".utf8))
    }

    func testFixedPointPressure() {
        XCTAssertEqual(FixedPoint.u16(0), 0)
        XCTAssertEqual(FixedPoint.u16(1), 0xFFFF)
        XCTAssertEqual(FixedPoint.u16(2), 0xFFFF) // clamped
    }
}
