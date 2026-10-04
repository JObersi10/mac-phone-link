import Foundation

/// Errors from shelling out to `adb`.
public enum AdbError: Error, CustomStringConvertible {
    case adbNotFound
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case noDevices
    case multipleDevices([String])

    public var description: String {
        switch self {
        case .adbNotFound:
            return "adb not found. Install Android platform-tools and/or set PHONELINK_ADB."
        case let .commandFailed(cmd, code, err):
            return "adb \(cmd) failed (exit \(code)): \(err)"
        case .noDevices:
            return "No Android device detected over adb. Plug in the phone and enable USB debugging."
        case let .multipleDevices(serials):
            return "Multiple devices: \(serials.joined(separator: ", ")). Pick one with serial."
        }
    }
}

/// Thin, synchronous wrapper around the `adb` executable. We intentionally
/// drive the real `adb` rather than reimplementing the ADB protocol: it is the
/// supported, stable interface to the device and keeps this app honest about
/// what it is doing (nothing the user could not type themselves).
public struct Adb {
    public let executable: String
    public let serial: String?

    public init(executable: String? = nil, serial: String? = nil) throws {
        if let explicit = executable ?? ProcessInfo.processInfo.environment["PHONELINK_ADB"] {
            self.executable = explicit
        } else if let found = Adb.locate() {
            self.executable = found
        } else {
            throw AdbError.adbNotFound
        }
        self.serial = serial
    }

    /// Search the app bundle, then PATH and common platform-tools locations.
    static func locate() -> String? {
        // Prefer the adb bundled inside the .app so the tool is self-contained
        // and version-consistent with the bundled scrcpy-server.
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("adb").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to PATH lookup via /usr/bin/env.
        return "adb"
    }

    @discardableResult
    public func run(_ args: [String], captureOutput: Bool = true) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable.hasPrefix("/") ? executable : "/usr/bin/env")
        var fullArgs = executable.hasPrefix("/") ? [] : [executable]
        if let serial { fullArgs += ["-s", serial] }
        fullArgs += args
        process.arguments = fullArgs

        let outPipe = Pipe(), errPipe = Pipe()
        if captureOutput { process.standardOutput = outPipe; process.standardError = errPipe }

        try process.run()
        process.waitUntilExit()

        let errData = captureOutput ? errPipe.fileHandleForReading.readDataToEndOfFile() : Data()
        let outData = captureOutput ? outPipe.fileHandleForReading.readDataToEndOfFile() : Data()

        guard process.terminationStatus == 0 else {
            throw AdbError.commandFailed(
                command: args.joined(separator: " "),
                exitCode: process.terminationStatus,
                stderr: String(decoding: errData, as: UTF8.self))
        }
        return String(decoding: outData, as: UTF8.self)
    }

    /// Serials of currently connected devices (state == "device").
    public func devices() throws -> [String] {
        let out = try run(["devices"])
        return out.split(separator: "\n").dropFirst().compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count == 2, parts[1].trimmingCharacters(in: .whitespaces) == "device"
            else { return nil }
            return String(parts[0])
        }
    }

    /// Resolve exactly one device, or throw a descriptive error.
    public func requireSingleDevice() throws -> String {
        if let serial { return serial }
        let list = try devices()
        switch list.count {
        case 0: throw AdbError.noDevices
        case 1: return list[0]
        default: throw AdbError.multipleDevices(list)
        }
    }

    public func push(localPath: String, remotePath: String) throws {
        try run(["push", localPath, remotePath])
    }

    /// Forward a local TCP port to a device-side abstract socket.
    public func forward(localPort: Int, toAbstract name: String) throws {
        try run(["forward", "tcp:\(localPort)", "localabstract:\(name)"])
    }

    public func removeForward(localPort: Int) throws {
        try run(["forward", "--remove", "tcp:\(localPort)"])
    }

    /// Package names of apps that have a launcher entry (the ones a user can
    /// open), via `cmd package query-activities` for the MAIN/LAUNCHER intent.
    public func launchableApps() throws -> [String] {
        let out = try run([
            "shell", "cmd", "package", "query-activities", "--brief",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.LAUNCHER"
        ])
        var packages = Set<String>()
        for token in out.split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" }) {
            guard token.contains("/") else { continue }
            let pkg = token.split(separator: "/").first.map(String.init) ?? ""
            if pkg.contains(".") { packages.insert(pkg) }
        }
        return packages.sorted()
    }
}
