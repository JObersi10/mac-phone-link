import Foundation

/// Options for one scrcpy-server instance. Each independent display/app gets
/// its own launch (and therefore its own SCID, tunnel port, and window).
public struct ServerOptions {
    /// Scrcpy connection id. Unique per concurrent session.
    public var scid: UInt32
    /// Local TCP port the Mac connects to (forwarded to the device socket).
    public var localPort: Int
    /// Max video dimension in px (scrcpy `max_size`). 0 = unlimited.
    public var maxSize: Int
    /// Target bitrate in bits/sec.
    public var videoBitRate: Int
    /// Max FPS.
    public var maxFps: Int
    /// Create a new virtual display of this size, e.g. "1920x1080" or
    /// "1920x1080/420". nil mirrors the physical display.
    public var newDisplay: String?
    /// Launch this app package on the (virtual) display, e.g. "org.videolan.vlc".
    public var startApp: String?
    /// Enable the control channel (input + clipboard).
    public var control: Bool
    /// Disable the virtual display's system decorations (e.g. Samsung DeX's
    /// launcher/taskbar) so a started app fills the display instead of showing
    /// the DeX desktop.
    public var noVdSystemDecorations: Bool

    public init(scid: UInt32, localPort: Int, maxSize: Int = 0,
                videoBitRate: Int = 8_000_000, maxFps: Int = 60,
                newDisplay: String? = nil, startApp: String? = nil,
                control: Bool = true, noVdSystemDecorations: Bool = false) {
        self.scid = scid
        self.localPort = localPort
        self.maxSize = maxSize
        self.videoBitRate = videoBitRate
        self.maxFps = maxFps
        self.newDisplay = newDisplay
        self.startApp = startApp
        self.control = control
        self.noVdSystemDecorations = noVdSystemDecorations
    }

    var socketName: String { String(format: "scrcpy_%08x", scid) }
}

/// Pushes scrcpy-server to the device and launches it. The server is a
/// separately-licensed Apache-2.0 artifact we do NOT vendor — the user (or the
/// build) supplies the matching jar. See NOTICE.md.
public struct ScrcpyServerLauncher {
    public let adb: Adb
    public let serverJarPath: String
    public let serverVersion: String
    private let remoteJar = "/data/local/tmp/phonelink-scrcpy-server.jar"

    public init(adb: Adb, serverJarPath: String, serverVersion: String) {
        self.adb = adb
        self.serverJarPath = serverJarPath
        self.serverVersion = serverVersion
    }

    /// Push the jar, set up the forward tunnel, and spawn the server process.
    /// Returns a `RunningServer` that captures the server's stdout/stderr — the
    /// server logs here say exactly why it exits (version mismatch, bad option,
    /// display errors), which is otherwise invisible.
    @discardableResult
    public func launch(_ opts: ServerOptions) throws -> RunningServer {
        try adb.push(localPath: serverJarPath, remotePath: remoteJar)
        try adb.forward(localPort: opts.localPort, toAbstract: opts.socketName)

        // scrcpy server CLI: key=value args, version as argv[0].
        // `tunnel_forward=true` makes the server LISTEN on the abstract socket
        // so our forwarded local port can connect into it.
        var serverArgs: [String] = [
            "CLASSPATH=\(remoteJar)",
            "app_process", "/", "com.genymobile.scrcpy.Server",
            serverVersion,
            "scid=\(String(format: "%08x", opts.scid))",
            "log_level=info",
            "tunnel_forward=true",
            "control=\(opts.control)",
            "audio=false",
            "video_codec=h264",
            "max_size=\(opts.maxSize)",
            "video_bit_rate=\(opts.videoBitRate)",
            "max_fps=\(opts.maxFps)",
            "cleanup=true"
        ]
        if let newDisplay = opts.newDisplay { serverArgs.append("new_display=\(newDisplay)") }
        if let startApp = opts.startApp { serverArgs.append("start_app=\(startApp)") }
        if opts.noVdSystemDecorations { serverArgs.append("no_vd_system_decorations=true") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var argv = [adb.executable]
        if let serial = adb.serial { argv += ["-s", serial] }
        argv += ["shell"] + serverArgs
        process.arguments = argv

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let commandLine = argv.joined(separator: " ")
        try process.run()
        return RunningServer(process: process, output: outputPipe, commandLine: commandLine)
    }

    public func tearDown(_ opts: ServerOptions) {
        try? adb.removeForward(localPort: opts.localPort)
    }
}

/// A launched scrcpy-server process plus a live capture of its merged
/// stdout/stderr. The captured text is the authoritative explanation when a
/// session fails to start or drops immediately.
public final class RunningServer {
    public let process: Process
    public let commandLine: String
    private let lock = NSLock()
    private var buffer = Data()

    init(process: Process, output: Pipe, commandLine: String) {
        self.process = process
        self.commandLine = commandLine
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.lock.lock(); self.buffer.append(data); self.lock.unlock()
        }
    }

    /// Everything the server has printed so far.
    public var log: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: buffer, as: UTF8.self)
    }

    public var isRunning: Bool { process.isRunning }

    public func terminate() {
        process.terminate()
    }
}
