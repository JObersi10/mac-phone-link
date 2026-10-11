// RemoteInputView — a transparent overlay that captures the Mac cursor and
// keyboard over the mirrored video and forwards normalized InputEventMessages.
//
// AppKit's view coordinates are bottom-left origin; video/phone coordinates are
// top-left, so we flip Y before normalizing. Points in the letterbox bars map
// to nil and are dropped (the cursor simply does nothing there), and moves are
// coalesced — together that's what keeps control stable instead of "going
// crazy" with out-of-range or flooded coordinates.
//
// SPDX-License-Identifier: MIT

#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI
import PhoneLinkProtos

public final class RemoteInputNSView: NSView {
    public var videoSize: CGSize = CGSize(width: 1080, height: 2400)
    public var onEvent: ((Maclink_Mirroring_V1_InputEventMessage) -> Void)?

    private var coalescer = MoveCoalescer()
    private var trackingAreaRef: NSTrackingArea?

    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    /// Flip Y (bottom-left → top-left) and normalize to video content [0,1].
    private func normalized(_ event: NSEvent) -> CGPoint? {
        let p = convert(event.locationInWindow, from: nil)
        let topLeft = CGPoint(x: p.x, y: bounds.height - p.y)
        return RemoteControl.normalize(viewPoint: topLeft, viewSize: bounds.size, videoSize: videoSize)
    }

    private func meta(_ event: NSEvent) -> Int32 {
        var m: Int32 = 0
        let f = event.modifierFlags
        if f.contains(.shift)   { m |= 1 }
        if f.contains(.control) { m |= 2 }
        if f.contains(.option)  { m |= 4 }
        if f.contains(.command) { m |= 8 }
        return m
    }

    // MARK: Mouse

    public override func mouseDown(with event: NSEvent) {
        guard let n = normalized(event) else { return }
        coalescer.reset()
        onEvent?(RemoteControl.pointer(.pointerDown, at: n, button: 0, metaState: meta(event)))
    }
    public override func rightMouseDown(with event: NSEvent) {
        guard let n = normalized(event) else { return }
        onEvent?(RemoteControl.pointer(.pointerDown, at: n, button: 1, metaState: meta(event)))
    }
    public override func mouseUp(with event: NSEvent) {
        guard let n = normalized(event) else { return }
        onEvent?(RemoteControl.pointer(.pointerUp, at: n, button: 0, metaState: meta(event)))
    }
    public override func rightMouseUp(with event: NSEvent) {
        guard let n = normalized(event) else { return }
        onEvent?(RemoteControl.pointer(.pointerUp, at: n, button: 1, metaState: meta(event)))
    }
    public override func mouseDragged(with event: NSEvent) { emitMove(event) }
    public override func mouseMoved(with event: NSEvent) { emitMove(event) }

    private func emitMove(_ event: NSEvent) {
        guard let n = normalized(event), coalescer.shouldSend(n) else { return }
        onEvent?(RemoteControl.pointer(.pointerMove, at: n, metaState: meta(event)))
    }

    public override func scrollWheel(with event: NSEvent) {
        guard let n = normalized(event) else { return }
        onEvent?(RemoteControl.scroll(at: n, dx: Float(event.scrollingDeltaX), dy: Float(event.scrollingDeltaY)))
    }

    // MARK: Keyboard

    public override func keyDown(with event: NSEvent) {
        onEvent?(RemoteControl.key(.keyDown, keyCode: Int32(event.keyCode), metaState: meta(event)))
    }
    public override func keyUp(with event: NSEvent) {
        onEvent?(RemoteControl.key(.keyUp, keyCode: Int32(event.keyCode), metaState: meta(event)))
    }
}

/// SwiftUI overlay. Place over the video surface; it forwards mapped events.
public struct RemoteInputView: NSViewRepresentable {
    private let videoSize: CGSize
    private let onEvent: (Maclink_Mirroring_V1_InputEventMessage) -> Void

    public init(videoSize: CGSize,
                onEvent: @escaping (Maclink_Mirroring_V1_InputEventMessage) -> Void) {
        self.videoSize = videoSize
        self.onEvent = onEvent
    }

    public func makeNSView(context: Context) -> RemoteInputNSView {
        let v = RemoteInputNSView()
        v.videoSize = videoSize
        v.onEvent = onEvent
        return v
    }

    public func updateNSView(_ nsView: RemoteInputNSView, context: Context) {
        nsView.videoSize = videoSize
        nsView.onEvent = onEvent
    }
}
#endif
