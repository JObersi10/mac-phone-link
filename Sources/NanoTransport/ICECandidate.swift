// ICECandidate — the ICE candidate model for the Nano transport. The candidate
// *type* raw values match the enum observed in LibNanoAPI
// (0=Host, 1=ServerReflexive, 2=PeerReflexive, 3=Relayed, 4=Manual); priority
// follows RFC 8445 §5.1.2. Transport flavors (`nano` direct UDP, `tcp-turn`,
// `tls-turn`) match the tokens seen in the binary.
//
// SPDX-License-Identifier: MIT

import Foundation

/// Candidate type — raw values match the LibNanoAPI enum ordering.
public enum ICECandidateType: Int, Sendable, CaseIterable {
    case host = 0
    case serverReflexive = 1
    case peerReflexive = 2
    case relayed = 3
    case manual = 4

    /// RFC 8445 recommended type preference (0–126).
    public var typePreference: Int {
        switch self {
        case .host: return 126
        case .peerReflexive: return 110
        case .serverReflexive: return 100
        case .relayed: return 0
        case .manual: return 126
        }
    }
}

/// How a candidate reaches its relay / peer. Mirrors the binary's transport tags.
public enum ICETransportKind: String, Sendable, CaseIterable {
    case udp = "nano"        // direct UDP ("nano")
    case tcpTurn = "tcp-turn"
    case tlsTurn = "tls-turn"
}

public struct ICECandidate: Equatable, Sendable {
    public var foundation: String
    public var component: Int            // 1 = RTP-equivalent; Nano uses per-channel
    public var type: ICECandidateType
    public var transport: ICETransportKind
    public var address: STUNAddress
    /// For reflexive/relayed candidates, the base (local) address they derive from.
    public var relatedAddress: STUNAddress?

    public init(foundation: String,
                component: Int = 1,
                type: ICECandidateType,
                transport: ICETransportKind = .udp,
                address: STUNAddress,
                relatedAddress: STUNAddress? = nil) {
        self.foundation = foundation
        self.component = component
        self.type = type
        self.transport = transport
        self.address = address
        self.relatedAddress = relatedAddress
    }

    /// RFC 8445 §5.1.2.1 priority:
    /// (2^24)*typePref + (2^8)*localPref + (256 - component).
    public func priority(localPreference: Int = 65535) -> UInt32 {
        let tp = UInt32(type.typePreference) << 24
        let lp = UInt32(localPreference & 0xFFFF) << 8
        let comp = UInt32(256 - component)
        return tp | lp | comp
    }
}

/// A local/remote candidate pair with its RFC 8445 check state.
public struct ICECandidatePair: Equatable, Sendable {
    public enum State: String, Sendable {
        case frozen, waiting, inProgress, succeeded, failed
    }
    public var local: ICECandidate
    public var remote: ICECandidate
    public var state: State = .frozen
    public var nominated: Bool = false

    public init(local: ICECandidate, remote: ICECandidate) {
        self.local = local
        self.remote = remote
    }

    /// RFC 8445 §6.1.2.3 pair priority. `controlling` picks G/D roles.
    public func priority(localIsControlling: Bool) -> UInt64 {
        let g = UInt64(localIsControlling ? local.priority() : remote.priority())
        let d = UInt64(localIsControlling ? remote.priority() : local.priority())
        return (UInt64(1) << 32) * min(g, d) + 2 * max(g, d) + (g > d ? 1 : 0)
    }
}
