import Foundation

/// One media packet carved out of the video socket, plus the flags from its
/// 12-byte header.
///
/// Header layout (scrcpy \(ScrcpyServer.pinnedVersion), `demuxer.c`):
///   - 8 bytes: flags + PTS. The two most-significant bits are flags:
///       bit 63 = config packet (codec setup: SPS/PPS, no displayable frame)
///       bit 62 = key frame
///     the remaining low bits are the presentation timestamp in microseconds.
///   - 4 bytes: payload length (big-endian u32)
///   - N bytes: the raw bitstream payload
public struct MediaPacket: Equatable, Sendable {
    public var isConfig: Bool
    public var isKeyFrame: Bool
    public var pts: UInt64
    public var payload: [UInt8]

    public init(isConfig: Bool, isKeyFrame: Bool, pts: UInt64, payload: [UInt8]) {
        self.isConfig = isConfig
        self.isKeyFrame = isKeyFrame
        self.pts = pts
        self.payload = payload
    }
}

public enum VideoFrameError: Error, Equatable {
    case shortHeader
    case shortPayload(expected: Int, got: Int)
}

/// Header size for a media packet.
public let mediaPacketHeaderSize = 12

private let configFlag: UInt64 = 1 << 63
private let keyFrameFlag: UInt64 = 1 << 62
private let ptsMask: UInt64 = (1 << 62) - 1

/// Parse a 12-byte media-packet header. Does not consume payload.
public func parseMediaPacketHeader(_ header: ArraySlice<UInt8>) throws
    -> (isConfig: Bool, isKeyFrame: Bool, pts: UInt64, payloadSize: Int)
{
    guard header.count >= mediaPacketHeaderSize else { throw VideoFrameError.shortHeader }
    let b = Array(header.prefix(mediaPacketHeaderSize))

    var ptsWord: UInt64 = 0
    for i in 0..<8 { ptsWord = (ptsWord << 8) | UInt64(b[i]) }

    let isConfig = (ptsWord & configFlag) != 0
    let isKeyFrame = (ptsWord & keyFrameFlag) != 0
    let pts = ptsWord & ptsMask

    var size: UInt32 = 0
    for i in 8..<12 { size = (size << 8) | UInt32(b[i]) }

    return (isConfig, isKeyFrame, pts, Int(size))
}

/// Incremental de-framer for the video socket. Feed it bytes as they arrive
/// off the TCP stream; it yields complete `MediaPacket`s as they complete.
public struct VideoDemuxer {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ data: [UInt8]) {
        buffer.append(contentsOf: data)
    }

    /// Pull the next complete packet, or nil if more bytes are needed.
    public mutating func next() throws -> MediaPacket? {
        guard buffer.count >= mediaPacketHeaderSize else { return nil }
        let (isConfig, isKeyFrame, pts, payloadSize) =
            try parseMediaPacketHeader(buffer[0..<mediaPacketHeaderSize])
        let total = mediaPacketHeaderSize + payloadSize
        guard buffer.count >= total else { return nil }

        let payload = Array(buffer[mediaPacketHeaderSize..<total])
        buffer.removeFirst(total)
        return MediaPacket(isConfig: isConfig, isKeyFrame: isKeyFrame,
                           pts: pts, payload: payload)
    }
}
