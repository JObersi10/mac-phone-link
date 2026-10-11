// ConnectionViewModel — bridges the transport layer (DCGConnection state +
// reassembled payloads) to observable UI state for the macOS app.
//
// It maps DCGChannelState to a display-friendly status and decodes
// notification-channel payloads into view models for the notifications list.
//
// SPDX-License-Identifier: MIT

import Foundation
import Combine
import PhoneLinkProtos
import DCGTransport

/// Display-friendly connection status.
public enum UIConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case disconnected(reason: String?)

    public var label: String {
        switch self {
        case .idle: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .disconnected(let reason): return reason.map { "Disconnected: \($0)" } ?? "Disconnected"
        }
    }

    public var isConnected: Bool { if case .connected = self { return true } else { return false } }

    init(_ channelState: DCGChannelState) {
        switch channelState {
        case .connecting: self = .connecting
        case .connected: self = .connected
        case .disconnected(let reason): self = .disconnected(reason: reason)
        }
    }
}

/// A single notification mirrored from the phone, shaped for display.
public struct NotificationItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let text: String
    public let appName: String
    public let postTime: Date

    public init(id: String, title: String, text: String, appName: String, postTime: Date) {
        self.id = id
        self.title = title
        self.text = text
        self.appName = appName
        self.postTime = postTime
    }

    init(_ info: Maclink_Notification_V1_NotificationInfo) {
        self.id = info.key.isEmpty ? UUID().uuidString : info.key
        self.title = info.title
        self.text = info.text.isEmpty ? info.bigText : info.text
        self.appName = info.appName
        self.postTime = Date(timeIntervalSince1970: TimeInterval(info.postTime) / 1000.0)
    }
}

@MainActor
public final class ConnectionViewModel: ObservableObject {
    @Published public private(set) var state: UIConnectionState = .idle
    @Published public private(set) var notifications: [NotificationItem] = []

    /// The handler_type that carries notification payloads.
    public var notificationHandlerType = "notification"

    private var connection: DCGConnection?

    public init() {}

    /// Observe a connection's lifecycle and reassembled payloads.
    public func bind(to connection: DCGConnection) {
        self.connection = connection
        connection.onStateChange = { [weak self] channelState in
            Task { @MainActor in self?.state = UIConnectionState(channelState) }
        }
        connection.onPayload = { [weak self] completed in
            guard let self else { return }
            guard completed.handlerType == self.notificationHandlerType else { return }
            let items = Self.decodeNotifications(from: completed.payload)
            Task { @MainActor in self.merge(items) }
        }
    }

    /// Start the bound connection (idempotent at the VM level).
    public func start() {
        state = .connecting
        connection?.start()
    }

    public func stop() {
        connection?.stop()
    }

    /// Merge newly received notifications, newest first, de-duplicated by id.
    func merge(_ items: [NotificationItem]) {
        var seen = Set(notifications.map(\.id))
        var result = notifications
        for item in items where !seen.contains(item.id) {
            result.insert(item, at: 0)
            seen.insert(item.id)
        }
        notifications = result
    }

    public func clear() { notifications = [] }

    /// Pure decoder: a notification-channel payload is a
    /// Maclink_Notification_V1_ResponseMessage; extract display items.
    public static func decodeNotifications(from payload: Data) -> [NotificationItem] {
        guard let resp = try? Maclink_Notification_V1_ResponseMessage(serializedBytes: payload) else {
            return []
        }
        return resp.notifications.map(NotificationItem.init)
    }
}
