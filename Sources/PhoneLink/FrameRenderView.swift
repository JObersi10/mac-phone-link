import AppKit
import CoreImage
import CoreVideo
import ScrcpyProtocol

/// A layer-backed view that displays decoded `CVImageBuffer` frames.
///
/// CoreImage → CGImage path for simplicity and correctness. The roadmap item
/// "Metal zero-copy renderer" replaces this with a `CAMetalLayer` drawing the
/// `CVPixelBuffer`'s IOSurface directly, which is where the latency win over
/// scrcpy's SDL path comes from.
class FrameRenderView: NSView {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private(set) var frameSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func render(_ imageBuffer: CVImageBuffer) {
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        frameSize = CGSize(width: width, height: height)

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        if Thread.isMainThread {
            layer?.contents = cgImage
        } else {
            DispatchQueue.main.async { [weak self] in self?.layer?.contents = cgImage }
        }
    }
}

/// FrameRenderView that forwards pointer / scroll / key events as control
/// messages. Coordinates are mapped to device pixels by `InputMapper`.
final class InteractiveFrameView: FrameRenderView {
    var onControlMessage: ((ControlMessage) -> Void)?
    var deviceSizeProvider: (() -> (UInt16, UInt16)?)?

    override var acceptsFirstResponder: Bool { true }

    private func mapper() -> InputMapper? {
        guard let (w, h) = deviceSizeProvider?() else { return nil }
        return InputMapper(deviceWidth: w, deviceHeight: h, viewSize: bounds.size)
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        guard let m = mapper() else { return }
        onControlMessage?(m.touch(.down, at: point(event)))
    }
    override func mouseDragged(with event: NSEvent) {
        guard let m = mapper() else { return }
        onControlMessage?(m.touch(.move, at: point(event)))
    }
    override func mouseUp(with event: NSEvent) {
        guard let m = mapper() else { return }
        onControlMessage?(m.touch(.up, at: point(event)))
    }
    override func scrollWheel(with event: NSEvent) {
        guard let m = mapper() else { return }
        onControlMessage?(m.scroll(at: point(event),
                                   deltaX: event.scrollingDeltaX,
                                   deltaY: event.scrollingDeltaY))
    }
    override func keyDown(with event: NSEvent) {
        guard let m = mapper() else { return }
        if let special = m.specialKey(event.keyCode) {
            onControlMessage?(special)
        } else if let chars = event.characters, !chars.isEmpty {
            onControlMessage?(m.text(chars))
        }
    }
}
