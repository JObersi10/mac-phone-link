import AppKit
import ScrcpyProtocol
import Streaming

/// One window = one session = one (physical or virtual) display.
final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    let session: DeviceSession
    let title: String
    var onClose: ((UInt32) -> Void)?

    private let renderView = InteractiveFrameView()

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
        window.contentView = renderView

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
        case .streaming: window?.title = title
        case .stopped: window?.title = "\(title) — stopped"
        case let .failed(message): window?.title = "\(title) — error"; log(message)
        case .idle: break
        }
    }

    private func log(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

    func windowWillClose(_ notification: Notification) {
        session.stop()
        onClose?(session.options.scid)
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
