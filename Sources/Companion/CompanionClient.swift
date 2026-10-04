import Foundation

/// Abstracts the paired, encrypted link to the phone. The production
/// implementation is a TLS socket on port 1716 established after mDNS discovery
/// (`_kdeconnect._udp`) and certificate-pinned pairing — that transport is the
/// next milestone (see docs/ROADMAP.md). The client logic below is written
/// against this protocol so it can be unit-tested with an in-memory fake.
public protocol CompanionTransport: AnyObject {
    /// Send one serialized, newline-terminated packet line.
    func send(_ line: Data) async throws
}

/// Callbacks for state the phone pushes to us.
public protocol CompanionDelegate: AnyObject {
    func companionDidReceiveNotification(_ notification: NotificationBody)
    func companionDidUpdateMedia(_ media: MprisBody)
    func companionDidUpdateBattery(_ battery: BatteryBody)
    func companionDidUpdateClipboard(_ text: String)
    func companionDidReceiveTelephony(_ event: TelephonyBody)
}

/// Default no-op implementations so delegates only implement what they need.
public extension CompanionDelegate {
    func companionDidReceiveNotification(_ notification: NotificationBody) {}
    func companionDidUpdateMedia(_ media: MprisBody) {}
    func companionDidUpdateBattery(_ battery: BatteryBody) {}
    func companionDidUpdateClipboard(_ text: String) {}
    func companionDidReceiveTelephony(_ event: TelephonyBody) {}
}

/// The capabilities this desktop advertises. Maps 1:1 to the Phone Link
/// features in scope.
public enum Capabilities {
    public static let incoming = [
        CompanionPacketType.battery,
        CompanionPacketType.notification,
        CompanionPacketType.mpris,
        CompanionPacketType.clipboard,
        CompanionPacketType.telephony,
        CompanionPacketType.connectivity
    ]
    public static let outgoing = [
        CompanionPacketType.findMyPhoneRequest,
        CompanionPacketType.notificationRequest,
        CompanionPacketType.mprisRequest,
        CompanionPacketType.clipboard,
        CompanionPacketType.ping
    ]
}

public final class CompanionClient {
    private let transport: CompanionTransport
    public weak var delegate: CompanionDelegate?

    public init(transport: CompanionTransport) {
        self.transport = transport
    }

    // MARK: - Outgoing feature commands

    /// Ring the phone (the "find my phone" button).
    public func ringPhone() async throws {
        try await send(type: CompanionPacketType.findMyPhoneRequest, body: FindMyPhoneBody())
    }

    /// Media transport controls for the "audio player" card.
    public func mediaCommand(player: String, action: String) async throws {
        try await send(type: CompanionPacketType.mprisRequest,
                       body: MprisRequestBody(player: player, action: action))
    }

    public func setMediaVolume(player: String, volume: Int) async throws {
        try await send(type: CompanionPacketType.mprisRequest,
                       body: MprisRequestBody(player: player, setVolume: volume))
    }

    public func requestNowPlaying(player: String) async throws {
        try await send(type: CompanionPacketType.mprisRequest,
                       body: MprisRequestBody(player: player, requestNowPlaying: true,
                                              requestPlayerList: true))
    }

    /// Dismiss a notification on the phone.
    public func dismissNotification(id: String) async throws {
        try await send(type: CompanionPacketType.notificationRequest,
                       body: NotificationRequestBody(cancel: id))
    }

    /// Push desktop clipboard to the phone.
    public func pushClipboard(_ text: String) async throws {
        try await send(type: CompanionPacketType.clipboard, body: ClipboardBody(content: text))
    }

    private func send<Body: Codable>(type: String, body: Body) async throws {
        let packet = NetworkPacket(type: type, body: body)
        try await transport.send(try packet.serializedLine())
    }

    // MARK: - Incoming routing

    /// Route one received JSON line to the appropriate delegate callback.
    public func handle(line: Data) {
        guard let header = try? JSONDecoder().decode(PacketHeader.self, from: line) else { return }
        switch header.type {
        case CompanionPacketType.notification:
            if let p = decode(NotificationBody.self, line) { delegate?.companionDidReceiveNotification(p) }
        case CompanionPacketType.mpris:
            if let p = decode(MprisBody.self, line) { delegate?.companionDidUpdateMedia(p) }
        case CompanionPacketType.battery:
            if let p = decode(BatteryBody.self, line) { delegate?.companionDidUpdateBattery(p) }
        case CompanionPacketType.clipboard, CompanionPacketType.clipboardConnect:
            if let p = decode(ClipboardBody.self, line) { delegate?.companionDidUpdateClipboard(p.content) }
        case CompanionPacketType.telephony:
            if let p = decode(TelephonyBody.self, line) { delegate?.companionDidReceiveTelephony(p) }
        default:
            break
        }
    }

    private func decode<Body: Codable>(_ type: Body.Type, _ line: Data) -> Body? {
        try? JSONDecoder().decode(NetworkPacket<Body>.self, from: line).body
    }
}
