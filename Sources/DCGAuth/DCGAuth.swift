// DCGAuth — MSA / Entra token acquisition wrapper for the Device Connectivity
// Gateway (DCG) scope, built on Microsoft's official MSAL library.
//
// SPDX-License-Identifier: MIT
//
// IMPORTANT — first-party constraint (read before wiring this up):
// The DCG resource (`https://dcg.microsoft.com`, scope `DCG.ReadWrite`) is a
// Microsoft FIRST-PARTY protected resource. A third-party / user-registered
// Entra app will almost certainly be refused consent for it
// (AADSTS65001 / AADSTS650057 / invalid_scope). This wrapper therefore takes a
// caller-supplied `clientId` and does NOT embed any first-party app identity —
// doing so would be impersonating the official app, not interoperating with it.
// Use `DCGScopes.diagnostic` first to prove the sign-in mechanics work, then try
// `DCGScopes.dcgReadWrite` to observe exactly how/whether the tenant grants it.

import Foundation
import MSAL

// MARK: - Configuration

public struct DCGAuthConfig: Sendable {
    /// Entra/MSA application (client) id. REQUIRED. Supply your own registration.
    public var clientId: String
    /// Authority. Defaults to the MSA consumers authority used by the mobile client.
    public var authority: URL
    /// Redirect URI registered for `clientId`. On macOS this is typically
    /// `msauth.<bundle-id>://auth`. If nil, MSAL uses its default.
    public var redirectUri: String?
    /// Optional keychain access group for token-cache sharing.
    public var keychainGroup: String?

    public init(
        clientId: String,
        authority: URL = URL(string: "https://login.microsoftonline.com/consumers")!,
        redirectUri: String? = nil,
        keychainGroup: String? = nil
    ) {
        self.clientId = clientId
        self.authority = authority
        self.redirectUri = redirectUri
        self.keychainGroup = keychainGroup
    }
}

public enum DCGScopes {
    /// The Device Connectivity Gateway resource scope used by Phone Link.
    public static let dcgReadWrite = ["https://dcg.microsoft.com/DCG.ReadWrite"]
    /// Universally-consentable scopes — use to validate the sign-in flow itself.
    public static let diagnostic = ["openid", "profile", "offline_access"]
}

// MARK: - Result token

public struct DCGToken: Sendable {
    public let accessToken: String
    public let expiresOn: Date?
    public let scopes: [String]
    /// Stable account identifier (MSAL home account id) for later silent calls.
    public let accountIdentifier: String?
    public let username: String?
    public let rawIdToken: String?

    /// Identity claims decoded from the id_token WITHOUT signature verification
    /// (inspection only). This is the client-side analog of the "device
    /// registration payload" — it carries the oid/tid/aud DCG keys off of.
    public var idTokenClaims: [String: Any]? {
        guard let idToken = rawIdToken else { return nil }
        return DCGToken.decodeJWTPayload(idToken)
    }

    static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }
}

// MARK: - Errors

public enum DCGAuthError: Error {
    case configuration(String)
    case noCachedAccount
    case msal(Error)
    case unexpectedEmptyResult
}

// MARK: - Authenticator

public final class DCGAuthenticator {
    private let application: MSALPublicClientApplication
    private let config: DCGAuthConfig

    public init(config: DCGAuthConfig) throws {
        self.config = config
        do {
            guard let authority = try? MSALAADAuthority(url: config.authority) else {
                throw DCGAuthError.configuration("Invalid authority URL: \(config.authority)")
            }
            let appConfig = MSALPublicClientApplicationConfig(
                clientId: config.clientId,
                redirectUri: config.redirectUri,
                authority: authority
            )
            if let group = config.keychainGroup {
                appConfig.cacheConfig.keychainSharingGroup = group
            }
            self.application = try MSALPublicClientApplication(configuration: appConfig)
        } catch let error as DCGAuthError {
            throw error
        } catch {
            throw DCGAuthError.msal(error)
        }
    }

    /// Acquire a token silently from the MSAL cache for a previously signed-in
    /// account. Throws `.noCachedAccount` if nothing is cached.
    public func acquireTokenSilent(
        scopes: [String] = DCGScopes.dcgReadWrite,
        accountIdentifier: String? = nil
    ) async throws -> DCGToken {
        let account = try cachedAccount(identifier: accountIdentifier)
        let params = MSALSilentTokenParameters(scopes: scopes, account: account)
        return try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: params) { result, error in
                Self.complete(result, error, continuation)
            }
        }
    }

    /// Interactive sign-in. The caller supplies `MSALWebviewParameters` built
    /// from its own window/anchor so this wrapper stays independent of the
    /// MSAL version's platform-specific anchor initializer.
    public func acquireTokenInteractive(
        scopes: [String] = DCGScopes.dcgReadWrite,
        webviewParameters: MSALWebviewParameters
    ) async throws -> DCGToken {
        let params = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webviewParameters)
        return try await withCheckedThrowingContinuation { continuation in
            application.acquireToken(with: params) { result, error in
                Self.complete(result, error, continuation)
            }
        }
    }

    /// Convenience: try silent first, fall back to interactive on cache miss.
    public func token(
        scopes: [String] = DCGScopes.dcgReadWrite,
        webviewParameters: MSALWebviewParameters,
        accountIdentifier: String? = nil
    ) async throws -> DCGToken {
        do {
            return try await acquireTokenSilent(scopes: scopes, accountIdentifier: accountIdentifier)
        } catch DCGAuthError.noCachedAccount {
            return try await acquireTokenInteractive(scopes: scopes, webviewParameters: webviewParameters)
        }
    }

    // MARK: Internals

    private func cachedAccount(identifier: String?) throws -> MSALAccount {
        if let id = identifier {
            guard let account = try? application.account(forIdentifier: id) else {
                throw DCGAuthError.noCachedAccount
            }
            return account
        }
        let accounts = (try? application.allAccounts()) ?? []
        guard let first = accounts.first else { throw DCGAuthError.noCachedAccount }
        return first
    }

    private static func complete(
        _ result: MSALResult?,
        _ error: Error?,
        _ continuation: CheckedContinuation<DCGToken, Error>
    ) {
        if let error = error {
            continuation.resume(throwing: DCGAuthError.msal(error))
            return
        }
        guard let result = result else {
            continuation.resume(throwing: DCGAuthError.unexpectedEmptyResult)
            return
        }
        let token = DCGToken(
            accessToken: result.accessToken,
            expiresOn: result.expiresOn,
            scopes: result.scopes,
            accountIdentifier: result.account.identifier,
            username: result.account.username,
            rawIdToken: result.idToken
        )
        continuation.resume(returning: token)
    }
}
