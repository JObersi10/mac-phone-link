import Foundation

/// The KDE Connect wire unit: a single-line JSON object
/// `{ "id": <ms>, "type": "kdeconnect.<x>", "body": { ... } }` terminated by a
/// newline. We reimplement the protocol (facts/interfaces are not
/// copyrightable); no KDE Connect (GPL) source is used. See NOTICE.md.
public struct NetworkPacket<Body: Codable>: Codable {
    public var id: Int64
    public var type: String
    public var body: Body

    public init(type: String, body: Body, id: Int64? = nil) {
        self.id = id ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.type = type
        self.body = body
    }

    /// Serialize to a newline-terminated JSON line, as the protocol requires.
    public func serializedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(0x0a) // '\n'
        return data
    }
}

/// Peeks only `id` and `type` so an incoming line can be routed to the right
/// typed body.
public struct PacketHeader: Codable {
    public let id: Int64
    public let type: String
}

public enum CompanionPacketType {
    public static let identity = "kdeconnect.identity"
    public static let pair = "kdeconnect.pair"
    public static let battery = "kdeconnect.battery"
    public static let findMyPhoneRequest = "kdeconnect.findmyphone.request"
    public static let notification = "kdeconnect.notification"
    public static let notificationRequest = "kdeconnect.notification.request"
    public static let mpris = "kdeconnect.mpris"
    public static let mprisRequest = "kdeconnect.mpris.request"
    public static let clipboard = "kdeconnect.clipboard"
    public static let clipboardConnect = "kdeconnect.clipboard.connect"
    public static let telephony = "kdeconnect.telephony"
    public static let sms = "kdeconnect.sms.messages"
    public static let connectivity = "kdeconnect.connectivity_report"
    public static let ping = "kdeconnect.ping"
}
