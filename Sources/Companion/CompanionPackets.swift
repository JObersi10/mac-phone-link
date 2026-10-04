import Foundation

// Typed bodies for the companion features shown in Phone Link's UI. Field names
// match the KDE Connect packet schemas so they interoperate with the KDE
// Connect Android app running on the phone.

public struct BatteryBody: Codable, Equatable {
    public var currentCharge: Int
    public var isCharging: Bool
    public var thresholdEvent: Int?
}

/// Ring-my-phone: an empty-bodied request that makes the phone ring.
public struct FindMyPhoneBody: Codable, Equatable {
    public init() {}
}

public struct NotificationBody: Codable, Equatable {
    public var id: String
    public var appName: String?
    public var title: String?
    public var text: String?
    public var ticker: String?
    public var isClearable: Bool?
    public var silent: Bool?
    public var time: String?
    /// Set on a packet that cancels/removes a previously posted notification.
    public var isCancel: Bool?

    enum CodingKeys: String, CodingKey {
        case id, appName, title, text, ticker, isClearable, silent, time
        case isCancel = "isCancel"
    }
}

/// Request to dismiss a notification on the phone.
public struct NotificationRequestBody: Codable, Equatable {
    public var cancel: String
    public init(cancel: String) { self.cancel = cancel }
}

/// Media/"audio player" state (MPRIS). The phone pushes player state; we send
/// commands back in `MprisRequestBody`.
public struct MprisBody: Codable, Equatable {
    public var player: String?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var isPlaying: Bool?
    public var canPause: Bool?
    public var canPlay: Bool?
    public var canGoNext: Bool?
    public var canGoPrevious: Bool?
    public var length: Int?
    public var pos: Int?
    public var volume: Int?
    /// Album art, sent as a URL/identifier by the phone.
    public var albumArtUrl: String?
    /// List of available players, present on the enumeration packet.
    public var playerList: [String]?
}

public struct MprisRequestBody: Codable, Equatable {
    public var player: String
    public var action: String?       // "Play", "Pause", "PlayPause", "Next", "Previous", "Stop"
    public var setVolume: Int?
    public var seek: Int?
    public var requestNowPlaying: Bool?
    public var requestPlayerList: Bool?

    public init(player: String, action: String? = nil, setVolume: Int? = nil,
                seek: Int? = nil, requestNowPlaying: Bool? = nil,
                requestPlayerList: Bool? = nil) {
        self.player = player
        self.action = action
        self.setVolume = setVolume
        self.seek = seek
        self.requestNowPlaying = requestNowPlaying
        self.requestPlayerList = requestPlayerList
    }
}

public struct ClipboardBody: Codable, Equatable {
    public var content: String
    public init(content: String) { self.content = content }
}

/// Incoming call / missed call / SMS event.
public struct TelephonyBody: Codable, Equatable {
    public var event: String          // "ringing", "talking", "missedCall", "sms"
    public var contactName: String?
    public var phoneNumber: String?
    public var messageBody: String?
}

public struct ConnectivityBody: Codable, Equatable {
    public struct Signal: Codable, Equatable {
        public var networkType: String?
        public var signalStrength: Int?
    }
    public var signalStrengths: [String: Signal]?
}

/// Identity packet exchanged on connect; `incomingCapabilities` /
/// `outgoingCapabilities` declare which features each side supports.
public struct IdentityBody: Codable, Equatable {
    public var deviceId: String
    public var deviceName: String
    public var deviceType: String
    public var protocolVersion: Int
    public var incomingCapabilities: [String]
    public var outgoingCapabilities: [String]

    public init(deviceId: String, deviceName: String, deviceType: String = "desktop",
                protocolVersion: Int = 7,
                incomingCapabilities: [String], outgoingCapabilities: [String]) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.protocolVersion = protocolVersion
        self.incomingCapabilities = incomingCapabilities
        self.outgoingCapabilities = outgoingCapabilities
    }
}
