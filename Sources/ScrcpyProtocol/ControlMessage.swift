import Foundation

/// Control messages sent client → device over the control socket.
///
/// Type tags and field layouts mirror scrcpy \(ScrcpyServer.pinnedVersion)
/// `app/src/control_msg.{h,c}`. Only the subset this client needs today is
/// implemented; the remaining tags are listed in `ControlMessageType` so the
/// gaps are explicit rather than silently missing.
public enum ControlMessageType: UInt8 {
    case injectKeycode = 0
    case injectText = 1
    case injectTouchEvent = 2
    case injectScrollEvent = 3
    case backOrScreenOn = 4
    case expandNotificationPanel = 5
    case expandSettingsPanel = 6
    case collapsePanels = 7
    case getClipboard = 8
    case setClipboard = 9
    case setDisplayPower = 10
    case rotateDevice = 11
    case uhidCreate = 12
    case uhidInput = 13
    case uhidDestroy = 14
    case openHardKeyboardSettings = 15
    case startApp = 16
    case resetVideo = 17
    // 18..=22: camera torch/zoom, resize display, scan file (not implemented)
}

/// Android `KeyEvent` action.
public enum KeyAction: UInt8 { case down = 0, up = 1 }

/// Android `MotionEvent` action (subset used for pointer injection).
public enum MotionAction: UInt8 { case down = 0, up = 1, move = 2 }

/// A normalized screen position. scrcpy sends the point together with the
/// frame size it was captured against so the device can rescale if the stream
/// resolution differs from the current display size.
public struct ScreenPosition: Equatable, Sendable {
    public var x: Int32
    public var y: Int32
    public var screenWidth: UInt16
    public var screenHeight: UInt16

    public init(x: Int32, y: Int32, screenWidth: UInt16, screenHeight: UInt16) {
        self.x = x; self.y = y
        self.screenWidth = screenWidth; self.screenHeight = screenHeight
    }

    func encode(into w: inout ByteWriter) {
        w.i32(x); w.i32(y); w.u16(screenWidth); w.u16(screenHeight)
    }
}

public enum ControlMessage {
    case injectKeycode(action: KeyAction, keycode: UInt32, repeatCount: UInt32, metaState: UInt32)
    case injectText(String)
    case injectTouch(action: MotionAction, pointerId: UInt64, position: ScreenPosition,
                     pressure: Float, actionButton: UInt32, buttons: UInt32)
    case injectScroll(position: ScreenPosition, hScroll: Float, vScroll: Float, buttons: UInt32)
    case backOrScreenOn(action: KeyAction)
    case getClipboard(copyKey: UInt8)
    case setClipboard(sequence: UInt64, paste: Bool, text: String)
    case startApp(name: String)

    /// Serialize to the exact bytes scrcpy-server expects on the control socket.
    public func serialize() -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case let .injectKeycode(action, keycode, repeatCount, metaState):
            w.u8(ControlMessageType.injectKeycode.rawValue)
            w.u8(action.rawValue)
            w.u32(keycode); w.u32(repeatCount); w.u32(metaState)

        case let .injectText(text):
            w.u8(ControlMessageType.injectText.rawValue)
            w.lengthPrefixedString(text, lengthBytes: 4)

        case let .injectTouch(action, pointerId, position, pressure, actionButton, buttons):
            w.u8(ControlMessageType.injectTouchEvent.rawValue)
            w.u8(action.rawValue)
            w.u64(pointerId)
            position.encode(into: &w)
            w.u16(FixedPoint.u16(pressure))
            w.u32(actionButton)
            w.u32(buttons)

        case let .injectScroll(position, hScroll, vScroll, buttons):
            w.u8(ControlMessageType.injectScrollEvent.rawValue)
            position.encode(into: &w)
            w.i16(FixedPoint.i16(hScroll))
            w.i16(FixedPoint.i16(vScroll))
            w.u32(buttons)

        case let .backOrScreenOn(action):
            w.u8(ControlMessageType.backOrScreenOn.rawValue)
            w.u8(action.rawValue)

        case let .getClipboard(copyKey):
            w.u8(ControlMessageType.getClipboard.rawValue)
            w.u8(copyKey)

        case let .setClipboard(sequence, paste, text):
            w.u8(ControlMessageType.setClipboard.rawValue)
            w.u64(sequence)
            w.u8(paste ? 1 : 0)
            w.lengthPrefixedString(text, lengthBytes: 4)

        case let .startApp(name):
            w.u8(ControlMessageType.startApp.rawValue)
            w.lengthPrefixedString(name, lengthBytes: 1)
        }
        return w.bytes
    }
}
