// DRSDiscovery — resolves the Device Registration Service endpoints for a
// tenant from the service's discovery document, so the nonce URL comes from the
// service rather than a hard-coded path (observed: DRSMetadataDiscoveryTask ->
// constructNonceUrlFromDrsMetadata).
//
// Discovery contract (Workplace Join):
//   GET https://<host>/<tenant>/EnrollmentServer/contract?api-version=1.0
// returns JSON whose DeviceRegistrationService.RegistrationEndpoint is the base
// the nonce request is built from.
//
// SPDX-License-Identifier: MIT

import Foundation

public struct DRSMetadata {
    public let registrationEndpoint: URL?
    public let raw: [String: Any]

    /// Build the nonce URL from the discovered registration endpoint
    /// (constructNonceUrlFromDrsMetadata): the endpoint plus `nonce=1`.
    public func nonceURL() -> URL? {
        guard let endpoint = registrationEndpoint,
              var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else { return nil }
        var items = comps.queryItems ?? []
        if !items.contains(where: { $0.name == "api-version" }) {
            items.append(URLQueryItem(name: "api-version", value: "1.0"))
        }
        items.append(URLQueryItem(name: "nonce", value: "1"))
        comps.queryItems = items
        return comps.url
    }
}

public final class DRSDiscoveryClient {
    private let transport: DRSTransport
    private let environment: DRSEnvironment

    public init(environment: DRSEnvironment = .production,
                transport: DRSTransport = URLSessionDRSTransport()) {
        self.environment = environment
        self.transport = transport
    }

    /// The discovery (contract) URL for a tenant.
    public func discoveryURL(tenant: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = environment.host
        comps.path = "/\(tenant)/EnrollmentServer/contract"
        comps.queryItems = [URLQueryItem(name: "api-version", value: "1.0")]
        return comps.url
    }

    /// Fetch and parse the DRS metadata for a tenant.
    public func discover(tenant: String) async throws -> DRSMetadata {
        guard let url = discoveryURL(tenant: tenant) else { throw DRSError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http): (Data, HTTPURLResponse)
        do {
            (data, http) = try await transport.data(for: request)
        } catch {
            throw DRSError.transport(error)
        }
        guard (200...299).contains(http.statusCode) else {
            throw DRSError.httpStatus(http.statusCode)
        }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> DRSMetadata {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DRSError.decoding
        }
        // DeviceRegistrationService.RegistrationEndpoint (case-tolerant).
        var endpoint: URL?
        if let drs = (obj["DeviceRegistrationService"] ?? obj["deviceRegistrationService"]) as? [String: Any] {
            if let s = (drs["RegistrationEndpoint"] ?? drs["registrationEndpoint"]) as? String {
                endpoint = URL(string: s)
            }
        }
        return DRSMetadata(registrationEndpoint: endpoint, raw: obj)
    }
}

public extension DRSNonceClient {
    /// Resolve the nonce URL via discovery, then request the nonce.
    func requestNonce(discoveringFor tenant: String,
                      discovery: DRSDiscoveryClient) async throws -> String {
        let metadata = try await discovery.discover(tenant: tenant)
        guard let url = metadata.nonceURL() else { throw DRSError.badURL }
        return try await requestNonce(url: url)
    }
}
