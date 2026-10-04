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

    func makeSession(newDisplay: String?, startApp: String?) throws -> DeviceSession {
        let jar = try locateServerJar()
        let adb = try Adb()
        _ = try adb.requireSingleDevice() // fail early with a clear message

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
            control: true)
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
        if let env = ProcessInfo.processInfo.environment["PHONELINK_SCRCPY_SERVER"],
           fm.isReadableFile(atPath: env) {
            return env
        }
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
