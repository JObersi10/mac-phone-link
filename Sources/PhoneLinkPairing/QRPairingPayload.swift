// QRPairingPayload — the pairing QR grammar.
//
// Clean-room model of the QR the PC/host displays and the Link to Windows phone
// app scans. Confirmed by decompiling the Android parsers (`FreQrCodeManager`,
// `FreParseDynamicLinkManager`, `DeeplinkResolver`): the QR is an **HTTPS
// dynamic link to a DCG host** carrying query parameters — NOT a bare
// `uaid=...` string (the scanner's `validateUri` rejects anything without a
// scheme and host, which is why a bare query reads as "invalid").
//
// Grammar (ideal flow):
//   https://dcg.microsoft.com/?vm=5&uaid=<prefix><16-char code>&ti=<guid>
//                             &r=5&apn=com.microsoft.appmanager
// Parameters (confirmed):
//   vm   view-model / flow mode (numeric; "5" = ideal flow)
//   uaid unique account id — the phone reads the LAST 16 chars as the YPP
//        pairing code (`FreQrCodeManager.getYPPPairingCode`)
//   ti   trace id (GUID)
//   r    ring ("5" = PROD)
//   apn  android package name (defaults to com.microsoft.appmanager)
//   tsft MSA transfer token — only for the account-transfer modes
//   cpsi cloud pin-session id — only for the proxy/transfer modes
//
// SPDX-License-Identifier: MIT

import Foundation

/// The `vm` (flow mode) values the dynamic-link parser recognizes.
public enum DynamicLinkMode: String, Sendable, CaseIterable {
    case oobeMvp = "1"
    case oobeMvpManual = "2"
    case idealFlow = "5"
    case minimalismOobe = "101"
    case minimalismOobeManual = "102"
}

/// The `r` (ring / environment) values.
public enum RingDefinition: String, Sendable, CaseIterable {
    case dev = "1"
    case team = "2"
    case canary = "3"
    case beta = "4"
    case prod = "5"
}

public struct QRPairingPayload: Equatable, Sendable {
    /// Length of the YPP pairing code carried in the tail of `uaid`.
    public static let pairingCodeLength = 16
    public static let defaultPackageName = "com.microsoft.appmanager"

    public var environment: DCGEnvironment
    public var mode: DynamicLinkMode
    public var ring: RingDefinition
    /// `uaid` — prefix + trailing 16-char pairing code.
    public var uaid: String
    /// `ti` — trace id (GUID). Generated if nil at encode time.
    public var traceId: String?
    /// `apn` — android package name.
    public var packageName: String
    /// `tsft` — MSA transfer token (transfer modes only).
    public var transferToken: String?
    /// `cpsi` — cloud pin-session id (proxy/transfer modes only). When set, the
    /// link is encoded in the real PC "Add device" `/dl` grammar.
    public var cloudPinSessionId: String?
    /// `et` — session expiry, Unix seconds (the `/dl` add-device flow only).
    public var expiry: Date?
    /// `mvc` — client min-version code (the `/dl` add-device flow only).
    public var minVersionCode: String?

    public init(uaid: String,
                environment: DCGEnvironment = .production,
                mode: DynamicLinkMode = .idealFlow,
                ring: RingDefinition = .prod,
                traceId: String? = nil,
                packageName: String = QRPairingPayload.defaultPackageName,
                transferToken: String? = nil,
                cloudPinSessionId: String? = nil,
                expiry: Date? = nil,
                minVersionCode: String? = nil) {
        self.uaid = uaid
        self.environment = environment
        self.mode = mode
        self.ring = ring
        self.traceId = traceId
        self.packageName = packageName
        self.transferToken = transferToken
        self.cloudPinSessionId = cloudPinSessionId
        self.expiry = expiry
        self.minVersionCode = minVersionCode
    }

    /// Build from an explicit pairing code plus optional prefix, producing a
    /// `uaid` whose last 16 chars are `pairingCode`.
    public init(pairingCode: String,
                prefix: String = "",
                environment: DCGEnvironment = .production,
                mode: DynamicLinkMode = .idealFlow,
                ring: RingDefinition = .prod,
                traceId: String? = nil) {
        precondition(pairingCode.count == Self.pairingCodeLength,
                     "pairing code must be \(Self.pairingCodeLength) chars")
        self.init(uaid: prefix + pairingCode, environment: environment,
                  mode: mode, ring: ring, traceId: traceId)
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

    // MARK: Encoding

    /// Build the full HTTPS dynamic-link URL the phone will accept. A trace id
    /// is generated if none was set.
    public func url() -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = environment.host
        // The real PC "Add device" link uses the /dl path + a cpsi PinSession
        // (mvc/cpsi/vm/et/r/ti, no uaid/apn), confirmed from a live PC. The
        // uaid "ideal flow" is the other entry point.
        if let cpsi = cloudPinSessionId {
            comps.path = "/dl"
            var items = [
                URLQueryItem(name: "mvc", value: minVersionCode ?? "0"),
                URLQueryItem(name: "cpsi", value: cpsi),
                URLQueryItem(name: "vm", value: mode.rawValue),
            ]
            if let et = expiry {
                items.append(URLQueryItem(name: "et", value: String(Int(et.timeIntervalSince1970))))
            }
            items.append(URLQueryItem(name: "r", value: ring.rawValue))
            // `ti` here is 32 lowercase hex, no dashes (not a dashed GUID).
            items.append(URLQueryItem(name: "ti", value: traceId ?? Self.randomTraceId32()))
            if let tsft = transferToken { items.append(URLQueryItem(name: "tsft", value: tsft)) }
            comps.queryItems = items
            return comps.url!
        }
        comps.path = "/"
        var items = [
            URLQueryItem(name: "vm", value: mode.rawValue),
            URLQueryItem(name: "uaid", value: uaid),
            URLQueryItem(name: "ti", value: traceId ?? UUID().uuidString),
            URLQueryItem(name: "r", value: ring.rawValue),
            URLQueryItem(name: "apn", value: packageName),
        ]
        if let tsft = transferToken { items.append(URLQueryItem(name: "tsft", value: tsft)) }
        comps.queryItems = items
        return comps.url!
    }

    /// A 32-char lowercase-hex trace id, the format the `/dl` add-device link uses.
    static func randomTraceId32() -> String {
        let hex = "0123456789abcdef"
        return String((0..<32).map { _ in hex.randomElement()! })
    }

    public func encoded() -> String { url().absoluteString }

    // MARK: Parsing

    /// Parse a scanned dynamic-link URL. Requires a DCG host and a `uaid`.
    public init?(parsing scanned: String) {
        guard let comps = URLComponents(string: scanned),
              let host = comps.host,
              let env = DCGEnvironment.allCases.first(where: { $0.host == host })
        else { return nil }
        let q = Dictionary(uniqueKeysWithValues:
            (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        // Accept either the uaid "ideal flow" (/) or the cpsi "add device"
        // flow (/dl). One of the two must be present.
        let uaid = q["uaid"] ?? ""
        let cpsi = q["cpsi"].flatMap { $0.isEmpty ? nil : $0 }
        guard !uaid.isEmpty || cpsi != nil else { return nil }
        let et = q["et"].flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
        self.init(
            uaid: uaid,
            environment: env,
            mode: q["vm"].flatMap(DynamicLinkMode.init(rawValue:)) ?? .idealFlow,
            ring: q["r"].flatMap(RingDefinition.init(rawValue:)) ?? .prod,
            traceId: q["ti"],
            packageName: q["apn"] ?? Self.defaultPackageName,
            transferToken: q["tsft"],
            cloudPinSessionId: cpsi,
            expiry: et,
            minVersionCode: q["mvc"]
        )
    }
}
