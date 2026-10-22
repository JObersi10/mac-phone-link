// DDSDeviceRegistration — step 2 of the account/device path: register this
// client into the DDS "Continuum" device graph so the paired phone can see it.
//
// Endpoint CONFIRMED live (docs/FINDINGS.md): the Windows client calls
//   GET https://continuum.dds.microsoft.com/Command/user/Continuum/Devices?scenario=…
// (resolves via Azure Front Door). Listing the graph is confirmed; the exact
// REGISTER body is not yet captured on the wire, so `DeviceRegistration` models
// a best-effort record from the `CryptoTrustRelationship` fields we documented
// and is marked accordingly. Auth is a caller-supplied header (the DCG MSA
// ticket) — no credential is embedded here.
//
// SPDX-License-Identifier: MIT

import Foundation

public struct DDSConfig: Sendable {
    public var host: URL
    /// Scenario query param the client tags requests with (observed but opaque).
    public var scenario: String?

    public init(host: URL = URL(string: "https://continuum.dds.microsoft.com")!,
                scenario: String? = nil) {
        self.host = host
        self.scenario = scenario
    }

    var devicesPath: String { "/Command/user/Continuum/Devices" }
}

/// A device entry in the Continuum graph. Field names follow the
/// `CryptoTrustRelationship` record we documented; the exact JSON schema of a
/// REGISTER request is UNVERIFIED (needs a live capture) — treat as best-effort.
public struct DeviceRegistration: Codable, Sendable, Equatable {
    public var selfClientId: String
    public var displayName: String
    public var platform: String
    /// Base64 of the client's self-signed device cert / public key (the
    /// `SelfSigned` trust identity from EnrollDevice).
    public var publicCertificate: String
    /// TrustType — one of LegacyD2D / AccountPairingD2D / AsyncD2D / A2D.
    public var trustType: String
    public var capabilities: [String]

    public init(selfClientId: String, displayName: String, platform: String = "macOS",
                publicCertificate: String, trustType: String = "AccountPairingD2D",
                capabilities: [String] = []) {
        self.selfClientId = selfClientId
        self.displayName = displayName
        self.platform = platform
        self.publicCertificate = publicCertificate
        self.trustType = trustType
        self.capabilities = capabilities
    }
}

public enum DDSError: Error, Equatable {
    case notConfigured
    case http(status: Int, body: String)
    case malformedResponse
}

/// REST client for the DDS device graph. Auth is injected: `authHeader` returns
/// the `(name, value)` the caller presents (e.g. the DCG MSA ticket). This type
/// embeds no identity or token.
public final class DDSDeviceRegistration: @unchecked Sendable {
    private let config: DDSConfig
    private let session: URLSession
    private let authHeader: @Sendable () async throws -> (String, String)

    public init(config: DDSConfig = DDSConfig(),
                session: URLSession = .shared,
                authHeader: @escaping @Sendable () async throws -> (String, String)) {
        self.config = config
        self.session = session
        self.authHeader = authHeader
    }

    private func devicesURL() -> URL {
        var comps = URLComponents(url: config.host.appendingPathComponent(config.devicesPath),
                                  resolvingAgainstBaseURL: false)!
        if let scenario = config.scenario {
            comps.queryItems = [URLQueryItem(name: "scenario", value: scenario)]
        }
        return comps.url!
    }

    private func authorized(_ req: inout URLRequest) async throws {
        let (name, value) = try await authHeader()
        req.setValue(value, forHTTPHeaderField: name)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    /// List devices in the account's graph. CONFIRMED endpoint (GET).
    public func listDevices() async throws -> Data {
        var req = URLRequest(url: devicesURL())
        req.httpMethod = "GET"
        try await authorized(&req)
        let (data, resp) = try await session.data(for: req)
        try Self.check(data, resp)
        return data
    }

    /// Register this device into the graph. Body schema UNVERIFIED — this sends
    /// the `DeviceRegistration` JSON as a best-effort; confirm against a live
    /// capture before relying on it.
    public func register(_ device: DeviceRegistration) async throws -> Data {
        var req = URLRequest(url: devicesURL())
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await authorized(&req)
        req.httpBody = try JSONEncoder().encode(device)
        let (data, resp) = try await session.data(for: req)
        try Self.check(data, resp)
        return data
    }

    private static func check(_ data: Data, _ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { throw DDSError.malformedResponse }
        guard (200...299).contains(http.statusCode) else {
            throw DDSError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
    }
}
