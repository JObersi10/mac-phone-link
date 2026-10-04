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
        session.onFrame = { [weak self] imageBuffer, _ in
            self?.renderView.render(imageBuffer) // render marshals to main
        }
        session.onStateChange = { [weak self] newState in
            DispatchQueue.main.async { self?.state = newState }
        }
        session.onLog = { AppLog.shared.log("[\(title)] \($0)") }
    }
}

/// The app's shared observable state. UI reads `@Published` properties; actions
/// drive the display plane (sessions) and, later, the companion plane.
final class AppModel: ObservableObject {
    @Published var devices: [String] = []
    @Published var selectedDevice: String?
    @Published var adbReady = false
    @Published var installedApps: [String] = []
    @Published var loadingApps = false
    @Published var sessions: [SessionBox] = []
    @Published var selectedTab: MainTab = .phone

    // Companion plane state (populated once the transport lands).
    @Published var nowPlaying: MprisBody?
    @Published var battery: BatteryBody?
    @Published var notifications: [NotificationBody] = []
    @Published var companionConnected = false

    @Published var lastError: String?

    let nowPlayingBridge = NowPlayingBridge()
    private let sessionManager = SessionManager()
    private var companion: CompanionClient?

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
            let apps = (try? Adb(serial: serial).launchableApps()) ?? []
            DispatchQueue.main.async {
                self.installedApps = apps
                self.loadingApps = false
                AppLog.shared.log("launchable apps: \(apps.count)")
            }
        }
    }

    var fullScreenSession: SessionBox? { sessions.first { $0.isFullScreen } }
    var appSessions: [SessionBox] { sessions.filter { !$0.isFullScreen } }

    func startFullMirror() {
        if fullScreenSession != nil { return }
        launch(newDisplay: nil, startApp: nil, title: "Phone Screen", isFullScreen: true)
    }

    /// Launch an app on its own virtual display and return the session id so the
    /// caller can open a dedicated window for it.
    @discardableResult
    func openApp(_ package: String, title: String? = nil) -> UUID? {
        let pkg = package.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pkg.isEmpty else { return nil }
        return launch(newDisplay: "1920x1080/320", startApp: pkg,
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

    // MARK: - Companion plane (wired once transport exists)

    func ringPhone() {
        guard let companion else { companionUnavailable(); return }
        Task { try? await companion.ringPhone() }
    }

    func mediaCommand(_ action: String) {
        guard let companion else { companionUnavailable(); return }
        Task { try? await companion.mediaCommand(player: nowPlaying?.player ?? "", action: action) }
    }

    private func companionUnavailable() {
        lastError = "Companion features (notifications, media, ring, battery) need the "
            + "companion app + transport, which is the next milestone. Mirroring works now."
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
}
