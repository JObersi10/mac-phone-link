import AppKit
import ScrcpyProtocol

/// Translates AppKit mouse / scroll / keyboard events into scrcpy control
/// messages, mapping view-local coordinates into device pixels.
///
/// Keyboard handling here is intentionally minimal: printable input is sent as
/// `injectText`, and a small set of navigation keys map to Android keycodes.
/// A full HID keyboard (via scrcpy's UHID messages) is a roadmap item.
struct InputMapper {
    let deviceWidth: UInt16
    let deviceHeight: UInt16
    let viewSize: CGSize

    private func devicePoint(from viewPoint: CGPoint) -> ScreenPosition {
        // AppKit origin is bottom-left; Android is top-left. Flip Y.
        let nx = viewSize.width > 0 ? viewPoint.x / viewSize.width : 0
        let ny = viewSize.height > 0 ? (1 - viewPoint.y / viewSize.height) : 0
        let dx = Int32(Double(deviceWidth) * Double(max(0, min(1, nx))))
        let dy = Int32(Double(deviceHeight) * Double(max(0, min(1, ny))))
        return ScreenPosition(x: dx, y: dy, screenWidth: deviceWidth, screenHeight: deviceHeight)
    }

    func touch(_ action: MotionAction, at viewPoint: CGPoint) -> ControlMessage {
        let pressure: Float = action == .up ? 0 : 1
        // AMOTION_EVENT_BUTTON_PRIMARY = 1
        let buttons: UInt32 = action == .up ? 0 : 1
        return .injectTouch(action: action, pointerId: 0xFFFF_FFFF_FFFF_FFFF,
                            position: devicePoint(from: viewPoint),
                            pressure: pressure, actionButton: 1, buttons: buttons)
    }

    func scroll(at viewPoint: CGPoint, deltaX: CGFloat, deltaY: CGFloat) -> ControlMessage {
        let h = Float(max(-1, min(1, deltaX / 10)))
        let v = Float(max(-1, min(1, deltaY / 10)))
        return .injectScroll(position: devicePoint(from: viewPoint),
                             hScroll: h, vScroll: v, buttons: 0)
    }

    func text(_ s: String) -> ControlMessage { .injectText(s) }

    /// Map a handful of AppKit key codes to Android keycodes.
    /// (AKEYCODE_* values.)
    func specialKey(_ keyCode: UInt16) -> ControlMessage? {
        let androidKeycode: UInt32
        switch keyCode {
        case 51: androidKeycode = 67    // delete -> KEYCODE_DEL
        case 36: androidKeycode = 66    // return -> KEYCODE_ENTER
        case 53: androidKeycode = 111   // esc -> KEYCODE_ESCAPE
        case 123: androidKeycode = 21   // left
        case 124: androidKeycode = 22   // right
        case 125: androidKeycode = 20   // down
        case 126: androidKeycode = 19   // up
        default: return nil
        }
        return .injectKeycode(action: .down, keycode: androidKeycode, repeatCount: 0, metaState: 0)
    }
}
