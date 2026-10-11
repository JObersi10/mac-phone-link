// DRSNonce — acquires the Device Registration Service nonce that the
// device-trust JWT binds (claim `nonce`). Observed flow: DRS discovery against
// enterpriseregistration.windows.net yields metadata, from which a nonce URL is
// constructed (constructNonceUrlFromDrsMetadata) and a nonce is requested
// (DRSNonceRequestHandler:requestNonce).
//
// The HTTP layer is injected (`DRSTransport`) so this is unit-testable without
// network access; a URLSession-backed default is provided.
//
// SPDX-License-Identifier: MIT

import Foundation

public enum DRSEnvironment: Sendable {
    case production
    case ppe
    case int

    /// Base host for DRS discovery.
    public var host: String {
        switch self {
        case .production: return "enterpriseregistration.windows.net"
        case .ppe:        return "enterpriseregistration-ppe.windows.net"
        case .int:        return "enterpriseregistration-int.windows.net"
        }
    }
}

public enum DRSError: Error {
    case badURL
    case emptyNonce
    case httpStatus(Int)
    case transport(Error)
    case decoding
}

/// Minimal async HTTP seam.
public protocol DRSTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-backed transport (default).
public struct URLSessionDRSTransport: DRSTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DRSError.transport(URLError(.badServerResponse))
        }
        return (data, http)
    }
}

public final class DRSNonceClient {
    private let transport: DRSTransport
    private let environment: DRSEnvironment

    public init(environment: DRSEnvironment = .production,
                transport: DRSTransport = URLSessionDRSTransport()) {
        self.environment = environment
        self.transport = transport
    }

    /// Construct the DRS nonce URL for a tenant/home authority.
    /// Shape: https://<host>/EnrollmentServer/device/<tenant>?api-version=1.0&nonce=1
    public func nonceURL(tenant: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = environment.host
        components.path = "/EnrollmentServer/device/\(tenant)"
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "1.0"),
            URLQueryItem(name: "nonce", value: "1"),
        ]
        return components.url
    }

    /// Request a nonce for the given tenant (or from an explicit nonce URL).
    public func requestNonce(tenant: String) async throws -> String {
        guard let url = nonceURL(tenant: tenant) else { throw DRSError.badURL }
        return try await requestNonce(url: url)
    }

    public func requestNonce(url: URL) async throws -> String {
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
        let nonce = try Self.parseNonce(from: data)
        guard !nonce.isEmpty else { throw DRSError.emptyNonce }
        return nonce
    }

    /// Accepts either a JSON body {"Nonce": "..."} / {"nonce": "..."} or a
    /// bare string body.
    static func parseNonce(from data: Data) throws -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let n = (obj["Nonce"] ?? obj["nonce"]) as? String { return n }
            throw DRSError.decoding
        }
        if let s = String(data: data, encoding: .utf8) {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        throw DRSError.decoding
    }
}
