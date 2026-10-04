import Foundation
import AdbBridge
import Streaming
import ScrcpyProtocol

enum SessionManagerError: Error, CustomStringConvertible {
    case serverJarNotFound

    var description: String {
        switch self {
        case .serverJarNotFound:
            return """
            scrcpy-server jar not found. Download the scrcpy-server matching version \
            \(ScrcpyServer.pinnedVersion) from the scrcpy releases page and place it at \
            ~/Library/Application Support/mac-phone-link/scrcpy-server, or set \
            PHONELINK_SCRCPY_SERVER to its path. (scrcpy-server is Apache-2.0; see NOTICE.md.)
            """
        }
    }
}

/// Allocates connection ids / ports and builds `DeviceSession`s. Keeps the
/// scrcpy-server jar discovery in one place.
final class SessionManager {
    private var nextScid: UInt32 = 1
    private var nextPort: Int = 27_183 // scrcpy's default base port
    private var active: [DeviceSession] = []

    func makeSession(newDisplay: String?, startApp: String?, serial: String?) throws -> DeviceSession {
        let jar = try locateServerJar()
        // Bind to the chosen device if given; otherwise require exactly one so a
        // developer with several adb targets gets a clear message instead of a
        // wrong target.
        let adb = try Adb(serial: serial)
        if serial == nil { _ = try adb.requireSingleDevice() }

        let launcher = ScrcpyServerLauncher(
            adb: adb, serverJarPath: jar, serverVersion: ScrcpyServer.pinnedVersion)

        let options = ServerOptions(
            scid: nextScid,
            localPort: nextPort,
            maxSize: 0,
            videoBitRate: 8_000_000,
            maxFps: 60,
            newDisplay: newDisplay,
            startApp: startApp,
            control: true,
            // For a single app, hide the virtual-display system UI (Samsung DeX
            // launcher/taskbar) so the app fills the window instead of DeX.
            noVdSystemDecorations: startApp != nil,
            // Make the virtual display adjustable so it relayouts to the window
            // (verified: `--flex-display`). Only meaningful for virtual displays.
            flexDisplay: newDisplay != nil)
        nextScid += 1
        nextPort += 1

        let session = DeviceSession(launcher: launcher, options: options)
        active.append(session)
        return session
    }

    func stopAll() {
        active.forEach { $0.stop() }
        active.removeAll()
    }

    private func locateServerJar() throws -> String {
        let fm = FileManager.default
        // 1. Bundled inside the .app (the normal, self-contained case).
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("scrcpy-server").path,
           fm.isReadableFile(atPath: bundled) {
            return bundled
        }
        // 2. Explicit override (useful for `swift run` during development).
        if let env = ProcessInfo.processInfo.environment["PHONELINK_SCRCPY_SERVER"],
           fm.isReadableFile(atPath: env) {
            return env
        }
        // 3. Application Support fallback.
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let candidate = appSupport?
            .appendingPathComponent("mac-phone-link/scrcpy-server").path,
           fm.isReadableFile(atPath: candidate) {
            return candidate
        }
        throw SessionManagerError.serverJarNotFound
    }
}

private extension FileManager {
    func isReadableFile(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }
}
