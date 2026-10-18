// ICEAgent — host-candidate gathering, checklist construction, and STUN
// connectivity-check building for the Nano ICE/STUN/TURN transport (RFC 8445).
//
// What's implemented now (standards-based, no captures needed):
//   • gathering host candidates from local interfaces,
//   • ordering candidate pairs by RFC 8445 pair priority,
//   • building a STUN binding connectivity-check (PRIORITY, ICE-CONTROLLING/
//     CONTROLLED, optional USE-CANDIDATE, MESSAGE-INTEGRITY, FINGERPRINT).
//
// What's deliberately left as a seam (fills in from the captured logs / native
// disasm — docs/EVIDENCE_PLAN.md, docs/FINDINGS.md):
//   • TURN Allocate/Refresh/CreatePermission/ChannelBind for relayed candidates,
//   • the Nano "pseudo-TLS" handshake carried over STUN/wrapper messages,
//   • the per-channel versioned Client/Server handshake packets.
// Socket I/O sits behind `STUNChecker` so the logic is testable without a network.
//
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Sends a STUN request to a destination and returns the response bytes.
/// A real implementation wraps a UDP socket (Network.framework); tests inject a stub.
public protocol STUNChecker: Sendable {
    func sendBindingRequest(_ request: Data, to address: STUNAddress) async throws -> Data
}

public struct ICECredentials: Sendable {
    public var ufrag: String
    public var password: String
    public init(ufrag: String, password: String) {
        self.ufrag = ufrag; self.password = password
    }
    /// A random short-term ICE credential pair (ufrag ≥4 chars, pwd ≥22 — RFC 8445).
    public static func random() -> ICECredentials {
        ICECredentials(ufrag: Self.randomToken(8), password: Self.randomToken(24))
    }
    static func randomToken(_ n: Int) -> String {
        let alpha = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        return String((0..<n).map { _ in alpha.randomElement()! })
    }
}

public final class ICEAgent {
    public let isControlling: Bool
    public let localCredentials: ICECredentials
    public var remoteCredentials: ICECredentials?
    /// Tie-breaker for role conflicts (RFC 8445 §6.1.1).
    public let tieBreaker: UInt64

    public init(isControlling: Bool,
                localCredentials: ICECredentials = .random(),
                tieBreaker: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        self.isControlling = isControlling
        self.localCredentials = localCredentials
        self.tieBreaker = tieBreaker
    }

    // MARK: Host candidate gathering

    /// Enumerate local IPv4/IPv6 interface addresses as host candidates bound to
    /// `port`. Loopback is skipped by default.
    public func gatherHostCandidates(port: UInt16, includeLoopback: Bool = false) -> [ICECandidate] {
        var out: [ICECandidate] = []
        #if canImport(Darwin)
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return out }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        var foundationCounter = 0
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let sa = cur.pointee.ifa_addr else { continue }
            let family = sa.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 else { continue }
            if !includeLoopback, (flags & IFF_LOOPBACK) != 0 { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let salen = socklen_t(family == UInt8(AF_INET) ? MemoryLayout<sockaddr_in>.size
                                                           : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(sa, salen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            var ip = String(cString: host)
            if let pct = ip.firstIndex(of: "%") { ip = String(ip[..<pct]) } // strip zone id
            let isV6 = family == UInt8(AF_INET6)
            // Skip IPv6 link-local by default (fe80::) — not useful across devices.
            if isV6, ip.lowercased().hasPrefix("fe80") { continue }
            foundationCounter += 1
            out.append(ICECandidate(
                foundation: "host\(foundationCounter)",
                type: .host,
                transport: .udp,
                address: STUNAddress(ip: ip, port: port, isIPv6: isV6)))
        }
        #endif
        return out
    }

    // MARK: Checklist

    /// Form the candidate checklist: every compatible local×remote pair, ordered
    /// by RFC 8445 pair priority (highest first), with the top pair set `.waiting`.
    public func formChecklist(local: [ICECandidate], remote: [ICECandidate]) -> [ICECandidatePair] {
        var pairs: [ICECandidatePair] = []
        for l in local {
            for r in remote where l.address.isIPv6 == r.address.isIPv6 && l.component == r.component {
                pairs.append(ICECandidatePair(local: l, remote: r))
            }
        }
        pairs.sort { $0.priority(localIsControlling: isControlling) > $1.priority(localIsControlling: isControlling) }
        if !pairs.isEmpty { pairs[0].state = .waiting }
        return pairs
    }

    // MARK: Connectivity-check building (RFC 8445 §7.2.2)

    /// Build the STUN binding request for a connectivity check on `pair`. Includes
    /// PRIORITY, the ICE role attribute, optional USE-CANDIDATE (controlling only),
    /// MESSAGE-INTEGRITY (keyed by the remote password), and FINGERPRINT.
    public func buildConnectivityCheck(for pair: ICECandidatePair,
                                       useCandidate: Bool = false) -> Data? {
        guard let remote = remoteCredentials else { return nil }
        var msg = STUNMessage(messageClass: .request, method: STUNMessage.methodBinding)

        // USERNAME = "remoteUfrag:localUfrag" (RFC 8445 §7.2.2).
        let username = "\(remote.ufrag):\(localCredentials.ufrag)"
        msg.attributes.append((STUNMessage.attrUsername, Data(username.utf8)))

        // PRIORITY (the priority this candidate would have as a peer-reflexive).
        var prio = Data()
        prio.appendBE(pair.local.priority())
        msg.attributes.append((STUNMessage.attrPriority, prio))

        // Role attribute + tie-breaker.
        var tb = Data()
        tb.appendBE(UInt32(tieBreaker >> 32)); tb.appendBE(UInt32(tieBreaker & 0xFFFF_FFFF))
        msg.attributes.append((isControlling ? STUNMessage.attrIceControlling
                                             : STUNMessage.attrIceControlled, tb))

        if isControlling && useCandidate {
            msg.attributes.append((STUNMessage.attrUseCandidate, Data()))
        }

        // MESSAGE-INTEGRITY keyed by the remote (short-term) password, then
        // FINGERPRINT. We build integrity first, then re-wrap to append the
        // fingerprint over the integrity-including message.
        let withMi = msg.encodedWithMessageIntegrity(key: Data(remote.password.utf8))
        return Self.appendFingerprint(to: withMi)
    }

    /// Append a FINGERPRINT attribute over an already-serialized STUN message,
    /// fixing up the header length to include it (RFC 5389 §15.5).
    static func appendFingerprint(to message: Data) -> Data {
        var m = message
        guard m.count >= 20 else { return m }
        // New length = current attrs length (header length field) + 8.
        let curLen = Int(m[2]) << 8 | Int(m[3])
        let newLen = curLen + 8
        m[2] = UInt8((newLen >> 8) & 0xFF); m[3] = UInt8(newLen & 0xFF)
        let crc = CRC32.checksum(m) ^ 0x5354_554E
        var fpVal = Data(); fpVal.appendBE(crc)
        STUNMessage.appendAttribute(&m, type: STUNMessage.attrFingerprint, value: fpVal)
        return m
    }

    /// Run a single connectivity check over the injected checker and report
    /// whether the peer answered with a success response carrying our txid.
    public func check(_ pair: ICECandidatePair, over checker: STUNChecker,
                      useCandidate: Bool = false) async -> Bool {
        guard let req = buildConnectivityCheck(for: pair, useCandidate: useCandidate),
              let sent = STUNMessage(decoding: req) else { return false }
        guard let respData = try? await checker.sendBindingRequest(req, to: pair.remote.address),
              let resp = STUNMessage(decoding: respData) else { return false }
        return resp.messageClass == .successResponse && resp.transactionID == sent.transactionID
    }
}
