// NanoChannel — the confirmed channel model of the Nano transport, recovered by
// static RE of the shipped `LibNanoAPI` (see docs/FINDINGS.md § "Nano transport
// + mirroring"). The real transport is a WebRTC-style ICE/STUN/TURN peer-to-peer
// path with a custom pseudo-TLS handshake (NOT plain QUIC): one `Connect` (client
// or server) multiplexes several *typed* channels, each opened with its own
// versioned handshake packet. These identifiers are protocol facts, not vendor
// source.
//
// NOTE: the existing `QUICNanoConnection` (Network.framework NWProtocolQUIC) is
// the wrong transport primitive for the media path per this finding; a faithful
// client needs an ICE agent + STUN/TURN + the pseudo-TLS handshake. This file
// models only the channel taxonomy, which is transport-independent.
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
