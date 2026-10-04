import Foundation
import CoreMedia
import ScrcpyProtocol
import AdbBridge
import VideoPipeline

/// Orchestrates one scrcpy session — one physical or virtual display, and
/// therefore one mirror view. Owns the launched server, the video and control
/// sockets, the demuxer, and the decoder.
///
/// Handshake (scrcpy \(ScrcpyServer.pinnedVersion), `tunnel_forward=true`):
///   1. connect the video (first) socket, read 1 dummy byte confirming the
///      server is listening behind the adb tunnel;
///   2. connect the control socket;
///   3. read the 64-byte device name from the video socket;
///   4. read the 4-byte codec id;
///   5. stream: a session packet carries the dimensions, media packets follow.
public final class DeviceSession {
    public enum State: Equatable { case idle, connecting, streaming, stopped, failed(String) }

    public let options: ServerOptions
    public private(set) var state: State = .idle
    public private(set) var videoSize: (width: UInt32, height: UInt32)?
    public private(set) var deviceName: String?

    public var onFrame: ((CVImageBuffer, CMTime) -> Void)?
    public var onDeviceClipboard: ((String) -> Void)?
    public var onStateChange: ((State) -> Void)?
    /// Diagnostic log line sink (wired to the app's log file).
    public var onLog: ((String) -> Void)?

    private let launcher: ScrcpyServerLauncher
    private let decoder = H264Decoder()
    private var server: RunningServer?
    private var videoSocket: SocketConnection?
    private var controlSocket: SocketConnection?
    private var demuxer = VideoDemuxer()
    private var running = false

    private let deviceNameFieldLength = 64

    public init(launcher: ScrcpyServerLauncher, options: ServerOptions) {
        self.launcher = launcher
        self.options = options
        decoder.onFrame = { [weak self] image, pts in self?.onFrame?(image, pts) }
    }

    private func log(_ message: String) { onLog?(message) }

    private func transition(_ newState: State) {
        state = newState
        if case let .failed(msg) = newState { log("session FAILED: \(msg)") }
        onStateChange?(newState)
    }

    public func start() async {
        transition(.connecting)
        do {
            log("launching scrcpy-server (scid=\(String(format: "%08x", options.scid)), " +
                "port=\(options.localPort), newDisplay=\(options.newDisplay ?? "none"), " +
                "startApp=\(options.startApp ?? "none"))")
            let server = try launcher.launch(options)
            self.server = server
            log("server cmd: \(server.commandLine)")

            let video = try await connectWithDummyByte()
            self.videoSocket = video

            if options.control {
                let control = SocketConnection(port: UInt16(options.localPort))
                try await control.start()
                self.controlSocket = control
                Task { await self.readControl(control) }
            }

            try await readDeviceMeta(video)
            try await readCodecId(video)

            transition(.streaming)
            running = true
            await streamVideo(video)
        } catch {
            transition(.failed(describe(error)))
        }
    }

    /// Combine the Swift error with whatever the server printed — the server log
    /// is usually the real reason (version mismatch, bad option, no display).
    private func describe(_ error: Error) -> String {
        var parts = [String(describing: error)]
        if let server {
            if !server.isRunning {
                parts.append("server exited early")
            }
            let serverLog = server.log.trimmingCharacters(in: .whitespacesAndNewlines)
            if !serverLog.isEmpty {
                parts.append("server output:\n\(serverLog)")
            }
        }
        return parts.joined(separator: " — ")
    }

    /// Connect the video socket and read the dummy byte. adb forward accepts the
    /// local connection even before the server is listening, so we retry until
    /// the dummy byte arrives (server is really up) or we give up.
    private func connectWithDummyByte() async throws -> SocketConnection {
        let maxAttempts = 15
        for attempt in 1...maxAttempts {
            if let server, !server.isRunning {
                throw SessionError.serverExited
            }
            let socket = SocketConnection(port: UInt16(options.localPort))
            do {
                try await socket.start()
                let dummy = try await socket.receiveExactly(1)
                if dummy.count == 1 {
                    log("connected (dummy byte received) on attempt \(attempt)")
                    return socket
                }
                socket.cancel()
            } catch {
                socket.cancel()
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw SessionError.timedOutWaitingForServer
    }

    private func readDeviceMeta(_ socket: SocketConnection) async throws {
        let raw = try await socket.receiveExactly(deviceNameFieldLength)
        guard raw.count == deviceNameFieldLength else { throw SessionError.shortHandshake }
        let nameBytes = raw.prefix { $0 != 0 }
        deviceName = String(decoding: nameBytes, as: UTF8.self)
        log("device name: \(deviceName ?? "")")
    }

    private func readCodecId(_ socket: SocketConnection) async throws {
        let raw = try await socket.receiveExactly(4)
        guard raw.count == 4 else { throw SessionError.shortHandshake }
        let codecId = (UInt32(raw[0]) << 24) | (UInt32(raw[1]) << 16)
            | (UInt32(raw[2]) << 8) | UInt32(raw[3])
        switch codecId {
        case 0: throw SessionError.videoDisabled
        case 1: throw SessionError.deviceConfigError
        default:
            let codec = VideoCodec(rawValue: codecId)
            log("codec id: 0x\(String(codecId, radix: 16)) (\(codec?.fourCC ?? "unknown"))")
        }
    }

    private func streamVideo(_ socket: SocketConnection) async {
        do {
            while running {
                let chunk = try await socket.receive()
                if chunk.isEmpty { log("video socket closed by peer"); break }
                demuxer.append(chunk)
                while let unit = try demuxer.next() {
                    switch unit {
                    case let .session(width, height):
                        videoSize = (width, height)
                        log("video size: \(width)x\(height)")
                    case let .media(packet):
                        try decoder.decode(packet)
                    }
                }
            }
        } catch {
            transition(.failed(describe(error)))
            return
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
            // Control channel errors are non-fatal to video.
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
        server?.terminate()
        launcher.tearDown(options)
        transition(.stopped)
    }
}

public enum SessionError: Error, CustomStringConvertible {
    case serverExited
    case timedOutWaitingForServer
    case shortHandshake
    case videoDisabled
    case deviceConfigError

    public var description: String {
        switch self {
        case .serverExited: return "scrcpy-server exited before streaming started"
        case .timedOutWaitingForServer: return "timed out waiting for scrcpy-server to listen"
        case .shortHandshake: return "handshake ended early (connection closed)"
        case .videoDisabled: return "server reported video disabled (codec id 0)"
        case .deviceConfigError: return "device could not configure the encoder (codec id 1)"
        }
    }
}
