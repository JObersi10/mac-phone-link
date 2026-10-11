// PairingCeremony — the device-to-device crypto-trust handshake state order.
//
// Clean-room model of the pairing channel ceremony. The sequence is taken from
// the observed state-processor ordering; the message payloads reuse the
// clean-room protobuf types already defined under Protos/maclink/sidechannel.
//
// SPDX-License-Identifier: MIT

import Foundation

/// Ordered states of the pairing-channel ceremony (host side).
public enum PairingCeremonyState: Int, Sendable, CaseIterable, Comparable {
    case checkPermission
    case getChannelInfo
    case openConnection
    case joinChannel          // JoinChannelWithMsa → JoinChannelResponse
    case sendDeviceInfo       // DeviceInfoExchange
    case sendCryptoInfo       // CryptoInfoExchange (public key / cert → trust)
    case sendNonce            // NonceMessage
    case waitForPing          // PingMessage from partner
    case commitCryptoTrust    // persist the crypto-trust relationship
    case succeeded
    case failed

    public static func < (lhs: PairingCeremonyState, rhs: PairingCeremonyState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The message kinds exchanged over the pairing channel, in ceremony order.
public enum PairingMessageKind: String, Sendable, CaseIterable {
    case joinChannelWithMsaRequest
    case joinChannelResponse
    case deviceInfoExchange
    case cryptoInfoExchange
    case nonce
    case ping
    case pairingResponse
    case exitChannelRequest
    case exitChannelResponse
    case partnerExited
}

/// A minimal forward-only driver over `PairingCeremonyState`. It encodes the
/// legal happy-path transitions; a real run also handles failure/exit at any
/// point (→ `.failed`).
public struct PairingCeremony: Sendable {
    public private(set) var state: PairingCeremonyState = .checkPermission

    public init() {}

    /// The next state on the success path, or nil if already terminal.
    public func nextState() -> PairingCeremonyState? {
        switch state {
        case .checkPermission:   return .getChannelInfo
        case .getChannelInfo:    return .openConnection
        case .openConnection:    return .joinChannel
        case .joinChannel:       return .sendDeviceInfo
        case .sendDeviceInfo:    return .sendCryptoInfo
        case .sendCryptoInfo:    return .sendNonce
        case .sendNonce:         return .waitForPing
        case .waitForPing:       return .commitCryptoTrust
        case .commitCryptoTrust: return .succeeded
        case .succeeded, .failed: return nil
        }
    }

    /// Advance along the success path. Returns false if already terminal.
    @discardableResult
    public mutating func advance() -> Bool {
        guard let next = nextState() else { return false }
        state = next
        return true
    }

    /// Abort the ceremony.
    public mutating func fail() { state = .failed }

    public var isTerminal: Bool { state == .succeeded || state == .failed }
}
