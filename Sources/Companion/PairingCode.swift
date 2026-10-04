import Foundation

/// The contents of the pairing QR code the Mac shows and the phone scans.
///
/// Format (our own URL scheme, AirSync-style):
///
///     maclink://<host>:<port>?name=<percent-encoded>&key=<base64-256bit>
///
/// The Mac is the server: it embeds the LAN IP + listening port + the shared
/// AES-256 key. The phone scans it, stores the key, and opens a TCP connection
/// to `host:port`, encrypting every frame with the key. For the USB fallback
/// the host is `127.0.0.1` reached through `adb reverse`.
public struct PairingCode: Equatable {
    public var host: String
    public var port: UInt16
    public var name: String
    public var base64Key: String

    public init(host: String, port: UInt16, name: String, base64Key: String) {
        self.host = host
        self.port = port
        self.name = name
        self.base64Key = base64Key
    }

    public static let scheme = "maclink"

    /// Encode to the QR string.
    public func encoded() -> String {
        var comps = URLComponents()
        comps.scheme = Self.scheme
        comps.host = host
        comps.port = Int(port)
        comps.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "key", value: base64Key),
        ]
        // URLComponents percent-encodes the query; base64 '+' must survive, and
        // `queryItems` encodes it as "%2B", which is correct and round-trips.
        return comps.string ?? "\(Self.scheme)://\(host):\(port)"
    }

    /// Parse a scanned/typed pairing string. Lenient about a missing name.
    public init?(parsing string: String) {
        guard let comps = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              comps.scheme == Self.scheme,
              let host = comps.host, !host.isEmpty,
              let port = comps.port, port > 0, port <= 65535,
              let key = comps.queryItems?.first(where: { $0.name == "key" })?.value, !key.isEmpty
        else { return nil }
        self.host = host
        self.port = UInt16(port)
        self.name = comps.queryItems?.first(where: { $0.name == "name" })?.value ?? "Mac"
        self.base64Key = key
    }
}
