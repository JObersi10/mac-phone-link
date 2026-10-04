import Foundation

/// The protocol in this module is pinned to a specific scrcpy server release.
///
/// scrcpy's wire format is NOT a stable public API — control-message layouts and
/// the video framing have changed between major versions. Pinning the version
/// here (and failing loudly on mismatch) is what keeps this module honest: the
/// byte layouts below are the ones that ship with exactly this server jar.
///
/// Source of truth to verify against:
///   https://github.com/Genymobile/scrcpy  (tag v\(ScrcpyServer.pinnedVersion))
///   app/src/control_msg.c   — control message serialization
///   app/src/demuxer.c       — video framing / packet headers
///   server/.../DeviceMessage — device → client messages (clipboard)
public enum ScrcpyServer {
    /// The scrcpy-server release this protocol module targets.
    ///
    /// 4.x is required for resizable virtual displays (the aspect-ratio button's
    /// live device-side resize via RESIZE_DISPLAY). The bundled scrcpy-server
    /// MUST match this string exactly — scrcpy-server validates the version
    /// argument against its own build and refuses to start on a mismatch.
    public static let pinnedVersion = "4.1"

    /// scrcpy-server speaks this SCID handshake value for app-selected sockets.
    /// (Informational; the launcher passes `scid=` on the command line.)
    public static let defaultScid: UInt32 = 0
}

/// Video codec identifiers sent as a big-endian u32 at the head of the video
/// socket (a 4-character code). Values from scrcpy's `demuxer.c`.
public enum VideoCodec: UInt32, Sendable {
    case h264 = 0x6832_3634 // "h264"
    case h265 = 0x6832_3635 // "h265"
    case av1  = 0x0061_7631 // "\0av1"
    case vp8  = 0x0076_7038 // "\0vp8"
    case vp9  = 0x0076_7039 // "\0vp9"

    public var fourCC: String {
        let v = rawValue
        let chars = [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff),
                     UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        return String(decoding: chars.filter { $0 != 0 }, as: UTF8.self)
    }
}
