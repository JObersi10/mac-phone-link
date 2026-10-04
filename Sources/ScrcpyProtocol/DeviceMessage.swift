import Foundation

/// Messages sent device → client on the control socket (the only socket used
/// in both directions). Layouts mirror scrcpy \(ScrcpyServer.pinnedVersion)
/// `DeviceMessage`.
public enum DeviceMessage: Equatable, Sendable {
    /// Device clipboard content (reply to GET_CLIPBOARD, or a push on change).
    case clipboard(String)
    /// Acknowledgement that a SET_CLIPBOARD with the given sequence was applied.
    case ackClipboard(sequence: UInt64)
    /// UHID output report (not interpreted yet).
    case uhidOutput(id: UInt16, data: [UInt8])

    enum TypeTag: UInt8 {
        case clipboard = 0
        case ackClipboard = 1
        case uhidOutput = 2
    }
}

public enum DeviceMessageParse: Equatable {
    /// A full message was parsed, consuming `consumed` bytes.
    case message(DeviceMessage, consumed: Int)
    /// Not enough bytes buffered yet.
    case needMore
}

/// Try to parse one device message from the front of `buffer`.
public func parseDeviceMessage(_ buffer: [UInt8]) -> DeviceMessageParse {
    guard let first = buffer.first,
          let tag = DeviceMessage.TypeTag(rawValue: first) else {
        // Unknown tag with at least one byte: surface as needMore so the caller
        // can decide; a real stream should never produce this.
        return .needMore
    }

    func readU32(_ offset: Int) -> UInt32? {
        guard buffer.count >= offset + 4 else { return nil }
        var v: UInt32 = 0
        for i in offset..<(offset + 4) { v = (v << 8) | UInt32(buffer[i]) }
        return v
    }
    func readU64(_ offset: Int) -> UInt64? {
        guard buffer.count >= offset + 8 else { return nil }
        var v: UInt64 = 0
        for i in offset..<(offset + 8) { v = (v << 8) | UInt64(buffer[i]) }
        return v
    }

    switch tag {
    case .clipboard:
        // type(1) + length(4) + utf8
        guard let len = readU32(1) else { return .needMore }
        let total = 1 + 4 + Int(len)
        guard buffer.count >= total else { return .needMore }
        let text = String(decoding: buffer[5..<total], as: UTF8.self)
        return .message(.clipboard(text), consumed: total)

    case .ackClipboard:
        // type(1) + sequence(8)
        guard let seq = readU64(1) else { return .needMore }
        return .message(.ackClipboard(sequence: seq), consumed: 9)

    case .uhidOutput:
        // type(1) + id(2) + size(2) + data
        guard buffer.count >= 5 else { return .needMore }
        let id = (UInt16(buffer[1]) << 8) | UInt16(buffer[2])
        let size = Int((UInt16(buffer[3]) << 8) | UInt16(buffer[4]))
        let total = 5 + size
        guard buffer.count >= total else { return .needMore }
        return .message(.uhidOutput(id: id, data: Array(buffer[5..<total])), consumed: total)
    }
}
