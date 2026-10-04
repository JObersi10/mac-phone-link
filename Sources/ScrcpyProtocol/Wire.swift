import Foundation

/// Low-level big-endian serialization helpers.
///
/// scrcpy's wire format is big-endian ("network order") throughout. These
/// helpers keep every multi-byte field going out in the same order so the
/// message structs below read like the C `control_msg.c` they mirror.
public struct ByteWriter {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func u8(_ v: UInt8) { bytes.append(v) }

    public mutating func u16(_ v: UInt16) {
        bytes.append(UInt8((v >> 8) & 0xff))
        bytes.append(UInt8(v & 0xff))
    }

    public mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }

    public mutating func u32(_ v: UInt32) {
        bytes.append(UInt8((v >> 24) & 0xff))
        bytes.append(UInt8((v >> 16) & 0xff))
        bytes.append(UInt8((v >> 8) & 0xff))
        bytes.append(UInt8(v & 0xff))
    }

    public mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }

    public mutating func u64(_ v: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((v >> UInt64(shift)) & 0xff))
        }
    }

    /// UTF-8 string prefixed with a big-endian u32 length (scrcpy "string" field).
    public mutating func lengthPrefixedString(_ s: String, lengthBytes: Int = 4) {
        let utf8 = Array(s.utf8)
        switch lengthBytes {
        case 1: u8(UInt8(min(utf8.count, 0xff)))
        case 4: u32(UInt32(utf8.count))
        default: fatalError("unsupported length prefix size \(lengthBytes)")
        }
        bytes.append(contentsOf: utf8.prefix(lengthBytes == 1 ? 0xff : utf8.count))
    }
}

/// Fixed-point conversions used for touch pressure and scroll deltas.
///
/// scrcpy encodes a normalized float into an integer so the wire stays
/// integer-only. Mirrors `sc_float_to_u16` / `sc_float_to_i16`.
public enum FixedPoint {
    /// Maps a value in [0, 1] to a u16 in [0, 0xffff].
    public static func u16(_ f: Float) -> UInt16 {
        let clamped = max(0, min(1, f))
        if clamped >= 1 { return 0xffff }
        return UInt16(clamped * 0x1_0000)
    }

    /// Maps a value in [-1, 1] to an i16 in [-0x8000, 0x7fff].
    public static func i16(_ f: Float) -> Int16 {
        let clamped = max(-1, min(1, f))
        if clamped >= 1 { return 0x7fff }
        if clamped <= -1 { return -0x8000 }
        return Int16(clamped * 0x8000)
    }
}
