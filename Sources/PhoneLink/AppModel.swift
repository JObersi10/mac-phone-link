import Foundation
import Combine
import AppKit
import AdbBridge
import Streaming
import Companion
import ScrcpyProtocol

/// Top tabs in the main window, mirroring Phone Link's layout.
enum MainTab: String, CaseIterable, Identifiable {
    case phone = "Phone Screen"
    case apps = "Apps"
    case messages = "Messages"
    case calls = "Calls"
    case photos = "Photos"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .phone: return "iphone"
        case .apps: return "square.grid.2x2"
        case .messages: return "message"
        case .calls: return "phone"
        case .photos: return "photo.on.rectangle"
        }
    }
}

/// One running mirror session plus the view that renders it. Owned by AppModel
/// and shown wherever that session needs to appear.
final class SessionBox: ObservableObject, Identifiable {
    let id = UUID()
    let session: DeviceSession
    let renderView = InteractiveFrameView()
    let isFullScreen: Bool
    @Published var title: String
    @Published var state: DeviceSession.State = .idle
    /// The decoded video dimensions, published once the first frame arrives so
    /// the window can lock itself to the phone's real aspect ratio.
    @Published var streamSize: CGSize?
    /// When true, the window is framed 16:9 (desktop/DeX-style) instead of the
    /// phone's native portrait aspect.
    @Published var preferLandscape = false

    /// The aspect ratio the window should hold: the live stream size, or 16:9
    /// if the user asked for desktop framing. Nil until the first frame.
    var windowAspect: CGSize? {
        if preferLandscape { return CGSize(width: 16, height: 9) }
        return streamSize
    }

    init(session: DeviceSession, title: String, isFullScreen: Bool) {
        self.session = session
        self.title = title
        self.isFullScreen = isFullScreen

        renderView.deviceSizeProvider = { [weak session] in
            guard let size = session?.videoSize else { return nil }
            return (UInt16(truncatingIfNeeded: size.width),
                    UInt16(truncatingIfNeeded: size.height))
        }
        renderView.onControlMessage = { [weak session] message in
            Task { await session?.send(message) }
        }
        session.onFrame = { [weak self, weak session] imageBuffer, _ in
            self?.renderView.render(imageBuffer) // render marshals to main
            if let size = session?.videoSize {
                let cg = CGSize(width: Int(size.width), height: Int(size.height))
                DispatchQueue.main.async {
                    if self?.streamSize != cg { self?.streamSize = cg }
                }
            }
        }
        session.onStateChange = { [weak self] newState in
            DispatchQueue.main.async { self?.state = newState }
        }
        session.onLog = { AppLog.shared.log("[\(title)] \($0)") }
    }

    /// Press an Android hardware/navigation key (down + up).
    func press(_ key: NavKey) {
        Task {
            await session.send(.injectKeycode(action: .down, keycode: key.rawValue,
                                              repeatCount: 0, metaState: 0))
            await session.send(.injectKeycode(action: .up, keycode: key.rawValue,
                                              repeatCount: 0, metaState: 0))
        }
    }
}

/// Android navigation keycodes (AKEYCODE_*).
enum NavKey: UInt32 {
    case back = 4
    case home = 3
    case recents = 187 // APP_SWITCH
}

/// The app's shared observable state. UI reads `@Published` properties; actions
/// drive the display plane (sessions) and, later, the companion plane.
final class AppModel: ObservableObject {
    @Published var devices: [String] = []
    @Published var selectedDevice: String?
    @Published var adbReady = false
    @Published var installedApps: [String] = []
    @Published var loadingApps = false
    @Published var phoneDisplaySpec: String?
    @Published var sessions: [SessionBox] = []
    @Published var selectedTab: MainTab = .phone

    // Companion plane state (populated once the transport lands).
    @Published var nowPlaying: MprisBody?
    @Published var battery: BatteryBody?
    @Published var notifications: [NotificationBody] = []
    @Published var companionConnected = false

    @Published var lastError: String?

    // Pairing / companion transport.
    @Published var pairingCode: PairingCode?
    @Published var showPairing = false

    let nowPlayingBridge = NowPlayingBridge()
    private let sessionManager = SessionManager()
    private var companion: CompanionClient?
    private var companionServer: TCPCompanionServer?
    private var companionCrypto: CompanionCrypto?

    /// Fixed companion port. Deterministic so the QR is stable and the USB
    /// fallback (`adb reverse tcp:<port> tcp:<port>`) is predictable.
    static let companionPort: UInt16 = 8787
    private let keyDefaultsKey = "companionAESKeyBase64"

    init() {
        nowPlayingBridge.onCommand = { [weak self] action in
            self?.mediaCommand(action)
        }
    }

    // MARK: - Display plane

    func refreshDevices() {
        do {
            let adb = try Adb()
            devices = try adb.devices()
            adbReady = true
            // Keep adb invisible: auto-pick a device so the user never has to
            // choose. The sidebar picker only matters when there are several.
            if let sel = selectedDevice, !devices.contains(sel) { selectedDevice = nil }
            if selectedDevice == nil { selectedDevice = devices.first }
            AppLog.shared.log("adb devices: \(devices.isEmpty ? "none" : devices.joined(separator: ", "))")
            if !devices.isEmpty { refreshApps() }
        } catch {
            devices = []
            adbReady = false
            AppLog.shared.log("adb unavailable: \(error)")
        }
    }

    /// Load the phone's launchable apps for the Apps tab (off the main thread).
    func refreshApps() {
        let serial = selectedDevice ?? devices.first
        loadingApps = true
        DispatchQueue.global().async {
            var apps: [String] = []
            var spec: String? = nil
            if let adb = try? Adb(serial: serial) {
                apps = (try? adb.launchableApps()) ?? []
                spec = try? adb.displaySpec()
            }
            DispatchQueue.main.async {
                self.installedApps = apps
                self.phoneDisplaySpec = spec
                self.loadingApps = false
                AppLog.shared.log("launchable apps: \(apps.count); display: \(spec ?? "unknown")")
            }
        }
    }

    var fullScreenSession: SessionBox? { sessions.first { $0.isFullScreen } }
    var appSessions: [SessionBox] { sessions.filter { !$0.isFullScreen } }

    /// Start mirroring the phone's main screen. Returns the session id so the
    /// caller opens it in its own window (like apps).
    @discardableResult
    func startFullMirror() -> UUID? {
        if let existing = fullScreenSession { return existing.id }
        return launch(newDisplay: nil, startApp: nil, title: "Phone Screen", isFullScreen: true)
    }

    /// Launch an app on its own virtual display and return the session id so the
    /// caller can open a dedicated window for it. The virtual display uses the
    /// phone's own resolution (portrait) so the app opens at the phone's aspect
    /// ratio — and so Samsung DeX (which only triggers on large landscape
    /// displays) does not take over.
    @discardableResult
    func openApp(_ package: String, title: String? = nil) -> UUID? {
        let pkg = package.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pkg.isEmpty else { return nil }
        let display = phoneDisplaySpec ?? "1080x2400/420"
        return launch(newDisplay: display, startApp: pkg,
                      title: title ?? prettyName(pkg), isFullScreen: false)
    }

    /// Prettify a package name for display, e.g. "org.videolan.vlc" → "Vlc".
    func prettyName(_ package: String) -> String {
        (package.split(separator: ".").last.map(String.init) ?? package).capitalized
    }

    @discardableResult
    private func launch(newDisplay: String?, startApp: String?, title: String, isFullScreen: Bool) -> UUID? {
        do {
            AppLog.shared.log("starting session '\(title)' on device \(selectedDevice ?? "(auto)")")
            let session = try sessionManager.makeSession(
                newDisplay: newDisplay, startApp: startApp, serial: selectedDevice)
            let box = SessionBox(session: session, title: title, isFullScreen: isFullScreen)
            sessions.append(box)
            Task { await session.start() }
            return box.id
        } catch {
            let message = String(describing: error)
            lastError = message
            AppLog.shared.log("failed to start session '\(title)': \(message)")
            return nil
        }
    }

    func session(id: UUID) -> SessionBox? { sessions.first { $0.id == id } }

    func close(_ box: SessionBox) {
        box.session.stop()
        sessions.removeAll { $0.id == box.id }
    }

    func stopAll() { sessions.forEach { $0.session.stop() }; sessions.removeAll() }

    // MARK: - Companion plane

    /// Start the TCP companion server (Mac = server) and show the pairing QR.
    /// Idempotent: if already running, just re-presents the code.
    func startPairing() {
        if companionServer == nil { startCompanionServer() }
        pairingCode = makePairingCode()
        showPairing = true
    }

    private func startCompanionServer() {
        let crypto = loadOrCreateCrypto()
        let server = TCPCompanionServer(crypto: crypto)
        let client = CompanionClient(transport: server)
        client.delegate = self
        server.onLine = { [weak client] line in client?.handle(line: line) }
        server.onConnected = { [weak self] connected in
            self?.companionConnected = connected
            if connected { self?.showPairing = false }
            AppLog.shared.log("companion \(connected ? "connected" : "disconnected")")
        }
        do {
            try server.start(preferredPort: Self.companionPort)
            self.companionServer = server
            self.companionCrypto = crypto
            self.companion = client
            AppLog.shared.log("companion server listening on :\(Self.companionPort)")
        } catch {
            lastError = "Couldn't start the companion server on port \(Self.companionPort): \(error)"
            AppLog.shared.log("companion server failed: \(error)")
        }
    }

    private func makePairingCode() -> PairingCode? {
        guard let crypto = companionCrypto else { return nil }
        let host = LocalNetwork.primaryIPv4Address() ?? "127.0.0.1"
        let name = Host.current().localizedName ?? "Mac"
        return PairingCode(host: host, port: Self.companionPort, name: name,
                           base64Key: crypto.base64Key)
    }

    /// Load the persisted AES key, or generate and persist a new one. Stored in
    /// UserDefaults for now (TODO: move to Keychain — tracked in ROADMAP).
    private func loadOrCreateCrypto() -> CompanionCrypto {
        if let b64 = UserDefaults.standard.string(forKey: keyDefaultsKey),
           let crypto = CompanionCrypto(base64Key: b64) {
            return crypto
        }
        let crypto = CompanionCrypto(key: CompanionCrypto.generateKey())
        UserDefaults.standard.set(crypto.base64Key, forKey: keyDefaultsKey)
        return crypto
    }

    func ringPhone() {
        guard let companion, companionConnected else { companionUnavailable(); return }
        Task { try? await companion.ringPhone() }
    }

    func mediaCommand(_ action: String) {
        guard let companion, companionConnected else { companionUnavailable(); return }
        Task { try? await companion.mediaCommand(player: nowPlaying?.player ?? "", action: action) }
    }

    private func companionUnavailable() {
        startPairing()
        lastError = "No phone is paired yet. Scan this QR code with the companion app "
            + "to connect notifications, media, ring and battery over Wi-Fi (or USB)."
    }
}

// MARK: - Companion callbacks (ready for when the transport delivers packets)
extension AppModel: CompanionDelegate {
    func companionDidUpdateMedia(_ media: MprisBody) {
        DispatchQueue.main.async {
            self.nowPlaying = media
            self.nowPlayingBridge.update(from: media)
        }
    }
    func companionDidUpdateBattery(_ b: BatteryBody) {
        DispatchQueue.main.async { self.battery = b }
    }
    func companionDidReceiveNotification(_ n: NotificationBody) {
        DispatchQueue.main.async {
            if n.isCancel == true {
                self.notifications.removeAll { $0.id == n.id }
            } else {
                self.notifications.insert(n, at: 0)
            }
        }
    }
    func companionDidUpdateClipboard(_ text: String) {
        DispatchQueue.main.async {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }
}
