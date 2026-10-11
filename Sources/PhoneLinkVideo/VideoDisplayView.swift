// VideoDisplayView — renders decoded/compressed video via
// AVSampleBufferDisplayLayer (which drives VideoToolbox internally) and exposes
// a SwiftUI wrapper for the mirroring surface.
//
// SPDX-License-Identifier: MIT

#if canImport(AVFoundation) && canImport(AppKit)
import Foundation
import AVFoundation
import AppKit
import CoreMedia
#if canImport(SwiftUI)
import SwiftUI
#endif

/// An NSView whose backing layer is an AVSampleBufferDisplayLayer.
public final class SampleBufferDisplayNSView: NSView {
    public let displayLayer = AVSampleBufferDisplayLayer()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer = displayLayer
    }

    /// Enqueue a sample buffer for display. The layer decodes + presents it.
    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        if displayLayer.isReadyForMoreMediaData {
            displayLayer.enqueue(sampleBuffer)
        }
    }

    public func flush() { displayLayer.flush() }
}

#if canImport(SwiftUI)
/// SwiftUI wrapper. Bind a VideoStreamController to receive the view and feed it.
public struct VideoDisplayView: NSViewRepresentable {
    private let onMakeView: (SampleBufferDisplayNSView) -> Void

    public init(onMakeView: @escaping (SampleBufferDisplayNSView) -> Void) {
        self.onMakeView = onMakeView
    }

    public func makeNSView(context: Context) -> SampleBufferDisplayNSView {
        let view = SampleBufferDisplayNSView()
        onMakeView(view)
        return view
    }

    public func updateNSView(_ nsView: SampleBufferDisplayNSView, context: Context) {}
}
#endif
#endif
