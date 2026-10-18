// NanoChannel — the confirmed channel model of the Nano transport, recovered by
// static RE of the shipped `LibNanoAPI` (see docs/FINDINGS.md § "Nano transport
// + mirroring"). The real transport is MsQuic: one `Connect` (client or server)
// that multiplexes several *typed* channels, rather than a single muxed byte
// stream. These identifiers are protocol facts, not vendor source.
//
// SPDX-License-Identifier: MIT

import Foundation

/// The role a `Connect` is opened in.
public enum NanoConnectRole: String, Sendable {
    case client   // CreateClientConnect
    case server   // CreateServerConnect
}

/// The typed channels multiplexed over a single Nano `Connect`, as exposed by
/// `LibNanoAPI` (`IVideoTargetChannel`, `IAudioTargetChannel`,
/// `IInputSourceChannel`, `IMessageChannel`, `IBlobChannel`/`IBlobStream`).
public enum NanoChannelType: String, CaseIterable, Sendable {
    /// Video frames from the phone to the PC (`IVideoTargetChannel`).
    case videoTarget
    /// Audio from the phone to the PC (`IAudioTargetChannel`).
    case audioTarget
    /// Input (pointer/keyboard) from the PC up to the phone (`IInputSourceChannel`).
    case inputSource
    /// Control messages — e.g. the mirroring `NearbyMessage` /
    /// `YourPhone.PhoneMirroring.Protocol.V1` app messages (`IMessageChannel`).
    case message
    /// Bulk/blob transfer (`IBlobChannel` / `IBlobStream`).
    case blob
}

/// A multiplexed channel identity on a Connect. `id` is the per-Connect
/// `ChannelId`; `type` its `ChannelType`.
public struct NanoChannel: Sendable, Equatable {
    public let id: UInt32
    public let type: NanoChannelType
    public init(id: UInt32, type: NanoChannelType) {
        self.id = id
        self.type = type
    }
}
