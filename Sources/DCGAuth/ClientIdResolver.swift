// ClientIdResolver — resolves the OAuth client id from the user's environment,
// so a client id is easy to supply WITHOUT any being hardcoded in this repo.
//
// Clean-room stance: this project ships no Microsoft first-party client id and
// no tool to extract one. The id is the caller's responsibility — use a client
// id you are authorized to use (e.g. your own app registration). Resolution
// order: explicit arg → env var → config file. If none is found, auth simply
// isn't configured; nothing is assumed or embedded.
//
// SPDX-License-Identifier: MIT

import Foundation

public enum ClientIdResolver {
    /// Env var a user can set to supply their client id.
    public static let environmentKey = "PHONELINK_CLIENT_ID"
    /// Default config path (`~/.config/phonelink/client_id`), one line.
    public static var defaultConfigURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/phonelink/client_id")
    }

    /// Resolve the client id: explicit value, then env var, then config file.
    /// Returns nil when the user has supplied none (auth stays unconfigured).
    public static func resolve(explicit: String? = nil,
                               environment: [String: String] = ProcessInfo.processInfo.environment,
                               configURL: URL? = nil) -> String? {
        if let explicit = clean(explicit) { return explicit }
        if let env = clean(environment[environmentKey]) { return env }
        let url = configURL ?? defaultConfigURL
        if let contents = try? String(contentsOf: url, encoding: .utf8),
           let fromFile = clean(contents.split(whereSeparator: \.isNewline).first.map(String.init)) {
            return fromFile
        }
        return nil
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
