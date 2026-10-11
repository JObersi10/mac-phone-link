// RemoteControl — maps the Mac cursor/keyboard to normalized input events sent
// back to the mirrored phone, and encodes them as InputEventMessage.
//
// The coordinate mapping is the thing that keeps control from "going crazy":
// the video is drawn with aspect-fit letterboxing inside the view, so a raw
// view point is NOT the phone coordinate. We compute the letterboxed video rect
// and normalize into [0,1] of the *content*, rejecting points in the black bars
// (returns nil → no event) and clamping to the frame. High-frequency moves are
// coalesced by a minimum delta so we don't flood the channel.
//
// SPDX-License-Identifier: MIT

#if canImport(CoreGraphics)
import Foundation
import CoreGraphics
import PhoneLinkProtos

public enum RemoteControl {

    /// The rect the video content actually occupies inside `viewSize` under
    /// aspect-fit (`.resizeAspect`), i.e. the content minus letterbox bars.
    public static func videoContentRect(viewSize: CGSize, videoSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0,
              videoSize.width > 0, videoSize.height > 0 else { return .zero }
        let scale = min(viewSize.width / videoSize.width,
                        viewSize.height / videoSize.height)
        let w = videoSize.width * scale
        let h = videoSize.height * scale
        return CGRect(x: (viewSize.width - w) / 2,
                      y: (viewSize.height - h) / 2,
                      width: w, height: h)
    }

    /// Normalize a view point (origin TOP-LEFT) to [0,1] of the video content.
    /// Returns nil if the point is outside the content (in a letterbox bar), so
    /// callers can simply drop the event instead of sending a garbage coord.
    public static func normalize(viewPoint p: CGPoint,
                                 viewSize: CGSize,
                                 videoSize: CGSize) -> CGPoint? {
        let rect = videoContentRect(viewSize: viewSize, videoSize: videoSize)
        guard rect.width > 0, rect.contains(p) else { return nil }
        let nx = (p.x - rect.minX) / rect.width
        let ny = (p.y - rect.minY) / rect.height
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

    // MARK: Event builders (normalized coords in)

    public static func pointer(_ kind: Maclink_Mirroring_V1_InputEventMessage.Kind,
                               at n: CGPoint,
                               button: Int32 = 0,
                               metaState: Int32 = 0) -> Maclink_Mirroring_V1_InputEventMessage {
        var m = Maclink_Mirroring_V1_InputEventMessage()
        m.kind = kind
        m.x = Float(n.x)
        m.y = Float(n.y)
        m.button = button
        m.metaState = metaState
        m.timestampMs = Self.now()
        return m
    }

    public static func scroll(at n: CGPoint, dx: Float, dy: Float) -> Maclink_Mirroring_V1_InputEventMessage {
        var m = Maclink_Mirroring_V1_InputEventMessage()
        m.kind = .scroll
        m.x = Float(n.x); m.y = Float(n.y)
        m.scrollDx = dx; m.scrollDy = dy
        m.timestampMs = Self.now()
        return m
    }

    public static func key(_ kind: Maclink_Mirroring_V1_InputEventMessage.Kind,
                           keyCode: Int32, metaState: Int32 = 0) -> Maclink_Mirroring_V1_InputEventMessage {
        var m = Maclink_Mirroring_V1_InputEventMessage()
        m.kind = kind
        m.keyCode = keyCode
        m.metaState = metaState
        m.timestampMs = Self.now()
        return m
    }

    static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

/// Coalesces pointer-move events: only emits a move when it has shifted by at
/// least `minDelta` in normalized space, bounding the event rate.
public struct MoveCoalescer {
    public let minDelta: CGFloat
    private var last: CGPoint?

    public init(minDelta: CGFloat = 0.005) { self.minDelta = minDelta }

    /// Returns true if this move is significant enough to send.
    public mutating func shouldSend(_ n: CGPoint) -> Bool {
        defer { last = n }
        guard let l = last else { return true }
        return abs(n.x - l.x) >= minDelta || abs(n.y - l.y) >= minDelta
    }

    public mutating func reset() { last = nil }
}
#endif
