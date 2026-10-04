import Foundation

/// One media packet carved out of the video socket, plus its flags.
///
/// Header layout (scrcpy \(ScrcpyServer.pinnedVersion), `demuxer.c`), 12 bytes:
///   - 8 bytes: flags + PTS (big-endian). Top bits of byte 0:
///       bit 63 = session packet marker (see `DemuxedUnit.session`)
///       bit 62 = config packet (codec setup: SPS/PPS, no displayable frame)
///       bit 61 = key frame
///     the remaining low 61 bits are the presentation timestamp in microseconds.
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

/// A unit pulled from the video socket: either a media packet, or a *session*
/// packet (sent at the start and on each rotation) carrying the current video
/// dimensions and no payload.
public enum DemuxedUnit: Equatable, Sendable {
    case session(width: UInt32, height: UInt32)
    case media(MediaPacket)
}

public enum VideoFrameError: Error, Equatable {
    case shortHeader
}

public let mediaPacketHeaderSize = 12

private let sessionFlag: UInt64 = 1 << 63
private let configFlag: UInt64 = 1 << 62
private let keyFrameFlag: UInt64 = 1 << 61
private let ptsMask: UInt64 = (1 << 61) - 1

/// Incremental de-framer for the video socket. Feed it bytes as they arrive;
/// it yields complete `DemuxedUnit`s. Note: it must be fed starting at the
/// first packet header — i.e. after the dummy byte, device name and codec id
/// have already been consumed (see `DeviceSession`).
public struct VideoDemuxer {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ data: [UInt8]) {
        buffer.append(contentsOf: data)
    }

    public mutating func next() throws -> DemuxedUnit? {
        guard buffer.count >= mediaPacketHeaderSize else { return nil }

        var ptsWord: UInt64 = 0
        for i in 0..<8 { ptsWord = (ptsWord << 8) | UInt64(buffer[i]) }
        var sizeField: UInt32 = 0
        for i in 8..<12 { sizeField = (sizeField << 8) | UInt32(buffer[i]) }

        if ptsWord & sessionFlag != 0 {
            // Session packet: bytes 4..7 = width, bytes 8..11 = height. No payload.
            let width = UInt32(ptsWord & 0xFFFF_FFFF)
            let height = sizeField
            buffer.removeFirst(mediaPacketHeaderSize)
            return .session(width: width, height: height)
        }

        let total = mediaPacketHeaderSize + Int(sizeField)
        guard buffer.count >= total else { return nil }

        let isConfig = ptsWord & configFlag != 0
        let isKeyFrame = ptsWord & keyFrameFlag != 0
        let pts = ptsWord & ptsMask
        let payload = Array(buffer[mediaPacketHeaderSize..<total])
        buffer.removeFirst(total)
        return .media(MediaPacket(isConfig: isConfig, isKeyFrame: isKeyFrame,
                                  pts: pts, payload: payload))
    }
}
