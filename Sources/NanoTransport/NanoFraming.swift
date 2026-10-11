// NanoFraming — length-prefixed message framing for the Nano direct transport.
//
// The direct (high-bandwidth) path carries discrete messages over a reliable,
// ordered QUIC stream. Each message is framed as a 4-byte big-endian unsigned
// length followed by exactly that many payload bytes. This matches the common
// shape of the vendor's stream framing (a varint/fixed length prefix per
// message); we use a fixed 32-bit prefix, which is unambiguous and simple.
//
// SPDX-License-Identifier: MIT

import Foundation

public enum NanoFraming {
    /// Maximum single-frame payload we will accept (guards against a bogus
    /// length prefix allocating unbounded memory). 64 MiB covers key frames.
    public static let maxFrameLength = 64 * 1024 * 1024

    public enum Error: Swift.Error, Equatable {
        case frameTooLarge(Int)
    }

    /// Prefix `payload` with its 4-byte big-endian length.
    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maxFrameLength else {
            throw Error.frameTooLarge(payload.count)
        }
        var out = Data(capacity: 4 + payload.count)
        let len = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: len) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }
}

/// Incremental decoder: feed arbitrary byte chunks as they arrive off the wire;
/// it emits whole frames as soon as each is complete. Not thread-safe; drive it
/// from a single serial queue (the transport's receive callback).
public struct NanoFrameDecoder {
    private var buffer = Data()

    public init() {}

    /// Append received bytes and return any frames that are now complete.
    public mutating func push(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []
        while true {
            guard buffer.count >= 4 else { break }
            let len = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let total = 4 + Int(len)
            if Int(len) > NanoFraming.maxFrameLength {
                throw NanoFraming.Error.frameTooLarge(Int(len))
            }
            guard buffer.count >= total else { break }
            // Slices keep the source indices; copy into a fresh, zero-based Data.
            let payload = Data(buffer[buffer.startIndex + 4 ..< buffer.startIndex + total])
            frames.append(payload)
            buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex + total)
        }
        return frames
    }

    /// Bytes buffered but not yet forming a complete frame (for diagnostics).
    public var pendingByteCount: Int { buffer.count }
}
