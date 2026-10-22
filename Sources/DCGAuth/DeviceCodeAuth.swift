// DeviceCodeAuth — OAuth 2.0 device authorization grant (RFC 8628) against the
// MSA consumers authority, for platforms without the Windows WAM broker (i.e.
// macOS). This is step 1 of the account/device path in docs/WINDOWS_COMPONENTS.md:
// obtain an MSA token with a CALLER-SUPPLIED client id.
//
// Clean-room note: the client id is a REQUIRED input with no default. This
// module embeds no Microsoft first-party identity — matching the protocol is
// interoperating; hardcoding their client id would be impersonation. The DCG
// broker-format scope (`<scope>&api-version=2.0&clientid=<id>`) that the real
// WAM path uses is layered on top of this by the caller via `brokerScope(_:)`.
//
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Configuration

public struct DeviceCodeConfig: Sendable {
    /// OAuth client id. REQUIRED — supply your own; never hardcoded here.
    public var clientId: String
    /// Authority base. Defaults to the MSA consumers authority the client uses.
    public var authority: URL
    /// Scopes to request (space-joined on the wire).
    public var scopes: [String]

    public init(clientId: String,
                authority: URL = URL(string: "https://login.microsoftonline.com/consumers")!,
                scopes: [String] = ["openid", "profile", "offline_access"]) {
        self.clientId = clientId
        self.authority = authority
        self.scopes = scopes
    }

    var deviceCodeEndpoint: URL { authority.appendingPathComponent("oauth2/v2.0/devicecode") }
    var tokenEndpoint: URL { authority.appendingPathComponent("oauth2/v2.0/token") }

    /// The DCG broker-format scope string the real WAM path presents, built
    /// from a base scope. Not guaranteed to work with a generic OAuth client —
    /// exposed so a caller can experiment on their own account.
    public func brokerScope(_ scope: String) -> String {
        "\(scope)&api-version=2.0&clientid=\(clientId)"
    }
}

// MARK: - Wire types

/// The device-code response the user acts on (RFC 8628 §3.2).
public struct DeviceCodeChallenge: Sendable, Decodable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expiresIn: Int
    public let interval: Int
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case message
    }
}

public struct DeviceCodeToken: Sendable, Decodable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int?
    public let scope: String?
    public let refreshToken: String?
    public let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

public enum DeviceCodeError: Error, Equatable {
    case http(status: Int, body: String)
    case oauth(code: String, description: String?)
    case expired
    case malformedResponse
}

// MARK: - Flow

public actor DeviceCodeAuth {
    private let config: DeviceCodeConfig
    private let session: URLSession

    public init(config: DeviceCodeConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Step 1: request a device code. Show `userCode` + `verificationURI` to the
    /// user, then call `pollForToken`.
    public func requestDeviceCode() async throws -> DeviceCodeChallenge {
        var req = URLRequest(url: config.deviceCodeEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form([
            "client_id": config.clientId,
            "scope": config.scopes.joined(separator: " "),
        ])
        let (data, resp) = try await session.data(for: req)
        try Self.checkStatus(data, resp)
        guard let challenge = try? JSONDecoder().decode(DeviceCodeChallenge.self, from: data) else {
            throw DeviceCodeError.malformedResponse
        }
        return challenge
    }

    /// Step 2: poll the token endpoint until the user approves, declines, or the
    /// code expires. Honors `authorization_pending` / `slow_down` per RFC 8628.
    public func pollForToken(_ challenge: DeviceCodeChallenge) async throws -> DeviceCodeToken {
        var intervalSeconds = max(challenge.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(challenge.expiresIn))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
            var req = URLRequest(url: config.tokenEndpoint)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Self.form([
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": config.clientId,
                "device_code": challenge.deviceCode,
            ])
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw DeviceCodeError.malformedResponse }
            if http.statusCode == 200,
               let token = try? JSONDecoder().decode(DeviceCodeToken.self, from: data) {
                return token
            }
            // Non-200: inspect the OAuth error code to decide pending vs fatal.
            let err = (try? JSONDecoder().decode(OAuthError.self, from: data))?.error ?? "invalid_request"
            switch err {
            case "authorization_pending":
                continue
            case "slow_down":
                intervalSeconds += 5
            case "expired_token":
                throw DeviceCodeError.expired
            default:
                let desc = (try? JSONDecoder().decode(OAuthError.self, from: data))?.description
                throw DeviceCodeError.oauth(code: err, description: desc)
            }
        }
        throw DeviceCodeError.expired
    }

    /// Convenience: request + poll, invoking `present` with the challenge so the
    /// caller can show the user code / open the verification URL.
    public func authenticate(
        present: @Sendable (DeviceCodeChallenge) -> Void
    ) async throws -> DeviceCodeToken {
        let challenge = try await requestDeviceCode()
        present(challenge)
        return try await pollForToken(challenge)
    }

    // MARK: Internals

    private struct OAuthError: Decodable {
        let error: String
        let description: String?
        enum CodingKeys: String, CodingKey { case error; case description = "error_description" }
    }

    private static func form(_ pairs: [String: String]) -> Data {
        var comps = URLComponents()
        comps.queryItems = pairs.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((comps.percentEncodedQuery ?? "").utf8)
    }

    private static func checkStatus(_ data: Data, _ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { throw DeviceCodeError.malformedResponse }
        guard (200...299).contains(http.statusCode) else {
            throw DeviceCodeError.http(status: http.statusCode,
                                       body: String(decoding: data, as: UTF8.self))
        }
    }
}
