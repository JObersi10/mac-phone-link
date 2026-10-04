import Foundation
import AppKit

/// Lightweight updater: checks the repo's GitHub Releases for a newer version
/// and points the user at the download. (A full in-place updater — Sparkle —
/// comes later with code signing; this works today without it.)
final class UpdateChecker {
    static let shared = UpdateChecker()
    let repo = "JObersi10/mac-phone-link"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    struct Release { let latest: String; let url: String; let isNewer: Bool }

    func check(completion: @escaping (Release?) -> Void) {
        func finish(_ r: Release?) { DispatchQueue.main.async { completion(r) } }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return finish(nil)
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return finish(nil) }
            let html = (json["html_url"] as? String) ?? "https://github.com/\(self.repo)/releases"
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let newer = Self.semverCompare(latest, self.currentVersion) > 0
            finish(Release(latest: latest, url: html, isNewer: newer))
        }.resume()
    }

    /// Show the result in an alert (call from a menu action).
    func checkAndPresent() {
        AppLog.shared.log("checking for updates (current \(currentVersion))")
        check { result in
            let alert = NSAlert()
            guard let result else {
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "Please try again later."
                alert.runModal(); return
            }
            if result.isNewer {
                alert.messageText = "Update available: \(result.latest)"
                alert.informativeText = "You have \(self.currentVersion). Open the releases page to download the latest."
                alert.addButton(withTitle: "View Releases")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: result.url) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                alert.messageText = "You're up to date"
                alert.informativeText = "\(self.currentVersion) is the latest version."
                alert.runModal()
            }
        }
    }

    /// Numeric dotted-version compare: 1 if a>b, -1 if a<b, 0 if equal.
    static func semverCompare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
