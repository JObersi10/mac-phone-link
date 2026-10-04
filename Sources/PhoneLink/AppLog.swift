import Foundation

/// App-wide diagnostic log. Opens a timestamped file on startup, mirrors every
/// line to it, and can export a copy to ~/Downloads from the Developer menu.
/// This is the primary way to see why a session failed (it captures the
/// scrcpy-server output).
final class AppLog {
    static let shared = AppLog()

    private let queue = DispatchQueue(label: "io.github.phonelink.log")
    private var lines: [String] = []
    private let startupFileURL: URL?
    private let dateFormatter: DateFormatter

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Startup log file under ~/Library/Logs/mac-phone-link/.
        let fm = FileManager.default
        let logsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/mac-phone-link", isDirectory: true)
        var fileURL: URL?
        if let logsDir {
            try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            fileURL = logsDir.appendingPathComponent("session-\(stamp).log")
        }
        startupFileURL = fileURL

        log("mac-phone-link started")
        if let startupFileURL { log("log file: \(startupFileURL.path)") }
    }

    func log(_ message: String) {
        let line = "[\(dateFormatter.string(from: Date()))] \(message)"
        queue.async {
            self.lines.append(line)
            if let url = self.startupFileURL {
                if let data = (line + "\n").data(using: .utf8) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    } else {
                        try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
    }

    func fullText() -> String {
        queue.sync { lines.joined(separator: "\n") }
    }

    /// Save a copy of the current log to ~/Downloads and return its URL.
    @discardableResult
    func saveToDownloads() throws -> URL {
        let fm = FileManager.default
        let downloads = try fm.url(for: .downloadsDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dest = downloads.appendingPathComponent("mac-phone-link-\(stamp).log")
        try fullText().write(to: dest, atomically: true, encoding: .utf8)
        log("saved log to \(dest.path)")
        return dest
    }
}
