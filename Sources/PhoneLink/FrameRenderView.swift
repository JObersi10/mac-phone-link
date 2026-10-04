import AppKit
import CoreImage
import CoreVideo

/// A layer-backed view that displays decoded `CVImageBuffer` frames.
///
/// This uses a CoreImage → CGImage path for simplicity and correctness. It is
/// deliberately the most obvious thing that works; the roadmap item "Metal
/// zero-copy renderer" (see docs/ROADMAP.md) replaces this with a
/// `CAMetalLayer` drawing the `CVPixelBuffer`'s IOSurface directly, which is
/// where the real latency win over scrcpy's SDL path comes from.
final class FrameRenderView: NSView {
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
        // Layer contents must be set on the main thread.
        if Thread.isMainThread {
            layer?.contents = cgImage
        } else {
            DispatchQueue.main.async { [weak self] in self?.layer?.contents = cgImage }
        }
    }
}
