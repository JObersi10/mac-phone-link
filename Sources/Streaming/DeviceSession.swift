import Foundation
import CoreMedia
import ScrcpyProtocol
import AdbBridge
import VideoPipeline

/// Orchestrates one scrcpy session — one physical or virtual display, and
/// therefore one mirror window. Owns the launched server process, the video
/// and control sockets, the demuxer, and the decoder.
///
/// Handshake note: with `tunnel_forward=true`, scrcpy-server listens on the
/// abstract socket and the client opens, in order, the video socket then the
/// control socket. The video socket begins with a codec id (u32) and the
/// initial video size (two u32s) before media packets start. This ordering is
/// version-specific; it is pinned to scrcpy \(ScrcpyServer.pinnedVersion) and
/// must be re-verified when the bundled server jar is bumped.
public final class DeviceSession {
    public enum State: Equatable { case idle, connecting, streaming, stopped, failed(String) }

    public let options: ServerOptions
    public private(set) var state: State = .idle
    public private(set) var videoSize: (width: UInt32, height: UInt32)?

    /// Decoded frames for the UI to render.
    public var onFrame: ((CVImageBuffer, CMTime) -> Void)?
    /// Device clipboard updates.
    public var onDeviceClipboard: ((String) -> Void)?
    public var onStateChange: ((State) -> Void)?

    private let launcher: ScrcpyServerLauncher
    private let decoder = H264Decoder()
    private var serverProcess: Process?
    private var videoSocket: SocketConnection?
    private var controlSocket: SocketConnection?
    private var demuxer = VideoDemuxer()
    private var running = false

    public init(launcher: ScrcpyServerLauncher, options: ServerOptions) {
        self.launcher = launcher
        self.options = options
        decoder.onFrame = { [weak self] image, pts in self?.onFrame?(image, pts) }
    }

    private func transition(_ newState: State) {
        state = newState
        onStateChange?(newState)
    }

    public func start() async {
        transition(.connecting)
        do {
            serverProcess = try launcher.launch(options)
            // Give the server a beat to bind its listening socket before we
            // connect through the forward tunnel.
            try await Task.sleep(nanoseconds: 300_000_000)

            let video = SocketConnection(port: UInt16(options.localPort))
            try await video.start()
            self.videoSocket = video

            if options.control {
                let control = SocketConnection(port: UInt16(options.localPort))
                try await control.start()
                self.controlSocket = control
                Task { await self.readControl(control) }
            }

            try await readVideoHeader(video)
            transition(.streaming)
            running = true
            await streamVideo(video)
        } catch {
            transition(.failed(String(describing: error)))
        }
    }

    private func readVideoHeader(_ socket: SocketConnection) async throws {
        // codec id (u32) + width (u32) + height (u32)
        let header = try await socket.receiveExactly(12)
        guard header.count == 12 else { return }
        func u32(_ o: Int) -> UInt32 {
            (UInt32(header[o]) << 24) | (UInt32(header[o+1]) << 16)
                | (UInt32(header[o+2]) << 8) | UInt32(header[o+3])
        }
        videoSize = (u32(4), u32(8))
    }

    private func streamVideo(_ socket: SocketConnection) async {
        do {
            while running {
                let chunk = try await socket.receive()
                if chunk.isEmpty { break }
                demuxer.append(chunk)
                while let packet = try demuxer.next() {
                    try decoder.decode(packet)
                }
            }
        } catch {
            transition(.failed(String(describing: error)))
        }
        if running { transition(.stopped) }
    }

    private func readControl(_ socket: SocketConnection) async {
        var buffer: [UInt8] = []
        do {
            while running || state == .connecting {
                let chunk = try await socket.receive()
                if chunk.isEmpty { break }
                buffer.append(contentsOf: chunk)
                loop: while true {
                    switch parseDeviceMessage(buffer) {
                    case let .message(msg, consumed):
                        buffer.removeFirst(consumed)
                        if case let .clipboard(text) = msg { onDeviceClipboard?(text) }
                    case .needMore:
                        break loop
                    }
                }
            }
        } catch {
            // Control channel errors are non-fatal to video; log via state only
            // if nothing else is running.
        }
    }

    public func send(_ message: ControlMessage) async {
        guard let controlSocket else { return }
        try? await controlSocket.send(message.serialize())
    }

    public func stop() {
        running = false
        videoSocket?.cancel()
        controlSocket?.cancel()
        serverProcess?.terminate()
        launcher.tearDown(options)
        transition(.stopped)
    }
}
