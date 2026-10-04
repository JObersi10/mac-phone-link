import AppKit
import ScrcpyProtocol
import Streaming

/// One window = one session = one (physical or virtual) display.
///
/// The window has a thin top bar with an aspect-ratio toggle:
///   • Native  — the phone's / virtual display's true ratio (from the stream).
///   • 16:9    — a fixed widescreen ratio.
/// The toggle is instant and never closes/reopens the session. Client-side it
/// relocks `window.contentAspectRatio`; for a virtual-display (per-app) session
/// it also sends scrcpy RESIZE_DISPLAY so the Android display actually relayouts
/// live (requires scrcpy >= 4.0). The decoder rebuilds on the new config packet,
/// so the switch is seamless.
final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    enum AspectMode { case native, sixteenNine }

    let session: DeviceSession
    let title: String
    var onClose: ((UInt32) -> Void)?

    private let container = MirrorContainerView()
    private let renderView = InteractiveFrameView()
    private let aspectButton = NSButton()
    private var aspectMode: AspectMode = .native

    init(session: DeviceSession, title: String) {
        self.session = session
        self.title = title

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 900),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = title
        window.center()
        super.init(window: window)

        window.delegate = self

        aspectButton.title = "16:9"
        aspectButton.bezelStyle = .rounded
        aspectButton.controlSize = .small
        aspectButton.target = self
        aspectButton.action = #selector(toggleAspect)

        container.bar.addSubview(aspectButton)
        container.renderView = renderView
        window.contentView = container

        renderView.deviceSizeProvider = { [weak session] in
            guard let size = session?.videoSize else { return nil }
            return (UInt16(truncatingIfNeeded: size.width),
                    UInt16(truncatingIfNeeded: size.height))
        }
        renderView.onControlMessage = { [weak session] message in
            Task { await session?.send(message) }
        }

        session.onFrame = { [weak self] imageBuffer, _ in
            self?.renderView.render(imageBuffer)
        }
        session.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.reflect(state) }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func reflect(_ state: DeviceSession.State) {
        switch state {
        case .connecting: window?.title = "\(title) — connecting…"
        case .streaming:
            window?.title = title
            // Now that we know the real size, lock to the phone's ratio.
            if aspectMode == .native { applyNativeAspect() }
        case .stopped: window?.title = "\(title) — stopped"
        case let .failed(message): window?.title = "\(title) — error"; log(message)
        case .idle: break
        }
    }

    // MARK: - Aspect ratio

    @objc private func toggleAspect() {
        aspectMode = (aspectMode == .native) ? .sixteenNine : .native
        switch aspectMode {
        case .native:
            aspectButton.title = "16:9"
            applyNativeAspect()
        case .sixteenNine:
            aspectButton.title = "Native"
            applySixteenNine()
        }
    }

    private func phoneAspect() -> CGFloat? {
        guard let size = session.videoSize, size.height > 0 else { return nil }
        return CGFloat(size.width) / CGFloat(size.height)
    }

    private func applyNativeAspect() {
        guard let ratio = phoneAspect(), let window else { return }
        setContentAspect(ratio, window: window)
        // Return the device to its native resolution if we had resized it.
        if session.options.newDisplay != nil, let size = session.videoSize {
            sendResize(width: size.width, height: size.height)
        }
    }

    private func applySixteenNine() {
        guard let window else { return }
        setContentAspect(16.0 / 9.0, window: window)
        // For a virtual display, actually change the device resolution so apps
        // relayout to widescreen (scrcpy >= 4.0). For a physical-screen mirror
        // this is a no-op on the device and only reframes the window locally.
        if session.options.newDisplay != nil {
            sendResize(width: 1920, height: 1080)
        }
    }

    private func setContentAspect(_ ratio: CGFloat, window: NSWindow) {
        // Account for the top bar so the *video* area keeps the ratio.
        let bar = MirrorContainerView.barHeight
        let currentContent = window.contentView?.bounds.size ?? window.frame.size
        let videoWidth = currentContent.width
        let videoHeight = videoWidth / ratio
        let newContentSize = NSSize(width: videoWidth, height: videoHeight + bar)
        window.contentAspectRatio = newContentSize
        window.setContentSize(newContentSize)
    }

    private func sendResize(width: UInt32, height: UInt32) {
        let w = UInt16(min(Int(UInt16.max), Int(width)))
        let h = UInt16(min(Int(UInt16.max), Int(height)))
        Task { await session.send(.resizeDisplay(width: w, height: h)) }
    }

    private func log(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

    func windowWillClose(_ notification: Notification) {
        session.stop()
        onClose?(session.options.scid)
    }
}

/// Container with a thin top bar and the render view below it.
final class MirrorContainerView: NSView {
    static let barHeight: CGFloat = 30
    let bar = NSView()
    var renderView: NSView? { didSet { layoutContents() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        addSubview(bar)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layout() {
        super.layout()
        layoutContents()
    }

    private func layoutContents() {
        let h = MirrorContainerView.barHeight
        bar.frame = NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        // Right-align the aspect button inside the bar.
        for sub in bar.subviews {
            (sub as? NSControl)?.sizeToFit()
            let bw = max(sub.frame.width, 56)
            sub.frame = NSRect(x: bar.bounds.width - bw - 8,
                               y: (h - 20) / 2, width: bw, height: 20)
        }
        renderView?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - h)
    }
}

/// FrameRenderView that forwards pointer / scroll / key events as control
/// messages.
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
