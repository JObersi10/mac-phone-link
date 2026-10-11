// QRPairingPayload — the pairing QR grammar.
//
// Clean-room model of the QR code the PC/host displays and the Link to Windows
// phone app scans. Derived from the observed *grammar* only (query-string keys
// and the pairing-code slice rule) — no vendor source is reproduced.
//
// The scanned string is a URL-style query with two keys:
//   uaid=<prefix><16-char YPP pairing code>   &   code=<MSA auth code>
// The phone extracts the **last 16 characters of `uaid`** as the YPP pairing
// code (the leading bytes are a zero-paddable prefix); `code` carries the MSA
// authorization code used to move the account onto the device.
//
// SPDX-License-Identifier: MIT

import Foundation

public struct QRPairingPayload: Equatable, Sendable {
    /// Length of the YPP pairing code carried in the tail of `uaid`.
    public static let pairingCodeLength = 16

    /// The full `uaid` value (prefix + trailing pairing code).
    public var uaid: String
    /// The MSA authorization code (`code=`), if present.
    public var msaCode: String?

    public init(uaid: String, msaCode: String? = nil) {
        self.uaid = uaid
        self.msaCode = msaCode
    }

    /// Build from an explicit pairing code plus optional prefix, producing a
    /// `uaid` whose last 16 chars are `pairingCode`.
    public init(pairingCode: String, prefix: String = "", msaCode: String? = nil) {
        precondition(pairingCode.count == Self.pairingCodeLength,
                     "pairing code must be \(Self.pairingCodeLength) chars")
        self.uaid = prefix + pairingCode
        self.msaCode = msaCode
    }

    /// The YPP pairing code: the final 16 characters of `uaid`. Nil if `uaid`
    /// is not longer than the code length (the phone rejects those).
    public var yppPairingCode: String? {
        guard uaid.count > Self.pairingCodeLength else { return nil }
        return String(uaid.suffix(Self.pairingCodeLength))
    }

    /// True when the prefix (everything before the trailing code) is non-empty
    /// and not all zeros — the validity signal the scanner uses.
    public var hasMeaningfulPrefix: Bool {
        guard uaid.count > Self.pairingCodeLength else { return false }
        let prefix = uaid.prefix(uaid.count - Self.pairingCodeLength)
        return !prefix.isEmpty && !prefix.allSatisfy { $0 == "0" }
    }

    // MARK: Parsing

    /// Parse a scanned string. Accepts a bare query (`uaid=…&code=…`) or a full
    /// URL/URI whose query (or fragment) carries the keys.
    public init?(parsing scanned: String) {
        let query = Self.queryPortion(of: scanned)
        var fields: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let key = String(kv[0])
            let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            fields[key] = value
        }
        guard let uaid = fields["uaid"], !uaid.isEmpty else { return nil }
        self.uaid = uaid
        self.msaCode = fields["code"]
    }

    private static func queryPortion(of s: String) -> Substring {
        if let q = s.firstIndex(of: "?") {
            let after = s[s.index(after: q)...]
            return after
        }
        if let h = s.firstIndex(of: "#") {
            return s[s.index(after: h)...]
        }
        return s[...]
    }

    // MARK: Encoding

    /// Serialize back to the `uaid=…&code=…` query grammar for display in a QR.
    public func encoded() -> String {
        var parts = ["uaid=\(uaid)"]
        if let code = msaCode { parts.append("code=\(code)") }
        return parts.joined(separator: "&")
    }
}
