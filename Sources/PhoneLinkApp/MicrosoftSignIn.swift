// MicrosoftSignIn — bridges PhoneLinkUI's injected `signInAction` to the real
// MSAL interactive flow in DCGAuth. Lives in the app layer (not PhoneLinkUI) so
// the UI stays decoupled from MSAL and AppKit window plumbing.
//
// Client id is NOT embedded (we never impersonate the first-party app). It is
// resolved, in priority order, from:
//   1. the PHONELINK_MSAL_CLIENT_ID environment variable,
//   2. the `PhoneLinkMSALClientId` UserDefaults key (the onboarding text field
//      writes here), or
//   3. a `PhoneLinkMSALClientId` entry in Info.plist.
// Register your own Entra application, add a macOS redirect URI of
// `msauth.com.maclink.phonelink://auth`, and supply its client id.
//
// Sign-in uses the universally-consentable diagnostic scopes so the mechanics
// actually complete and return an account; the DCG resource scope is requested
// separately by the transport layer (and may be refused — see DCGAuth.swift).
//
// SPDX-License-Identifier: MIT

#if canImport(AppKit) && canImport(MSAL)
import Foundation
import AppKit
import MSAL
import DCGAuth

@MainActor
public enum MicrosoftSignIn {
    /// UserDefaults / Info.plist key holding the Entra client id.
    public static let clientIdDefaultsKey = "PhoneLinkMSALClientId"

    public enum ConfigError: LocalizedError {
        case missingClientId
        case noPresentationAnchor

        public var errorDescription: String? {
            switch self {
            case .missingClientId:
                return "No Microsoft client id configured. Register your own Entra "
                    + "app (redirect msauth.com.maclink.phonelink://auth) and paste "
                    + "its client id below, or set PHONELINK_MSAL_CLIENT_ID."
            case .noPresentationAnchor:
                return "Could not find a window to present the sign-in sheet."
            }
        }
    }

    /// The resolved client id, or nil if none is configured anywhere.
    public static func resolvedClientId() -> String? {
        if let env = ProcessInfo.processInfo.environment["PHONELINK_MSAL_CLIENT_ID"],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env
        }
        if let stored = UserDefaults.standard.string(forKey: clientIdDefaultsKey),
           !stored.trimmingCharacters(in: .whitespaces).isEmpty {
            return stored
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: clientIdDefaultsKey) as? String,
           !plist.trimmingCharacters(in: .whitespaces).isEmpty {
            return plist
        }
        return nil
    }

    private static let redirectUri = "msauth.com.maclink.phonelink://auth"

    /// Build the closure that `OnboardingViewModel.signInAction` expects:
    /// performs an interactive MSAL sign-in and returns the account's username.
    public static func makeSignInAction(
        scopes: [String] = DCGScopes.diagnostic
    ) -> () async throws -> String {
        return {
            guard let clientId = resolvedClientId() else {
                throw ConfigError.missingClientId
            }
            // Matches the keychain-access-groups entitlement in
            // scripts/PhoneLink.entitlements, so MSAL's token cache persists in a
            // real (Developer ID signed) build. Harmless for ad-hoc builds.
            let config = DCGAuthConfig(
                clientId: clientId,
                redirectUri: redirectUri,
                keychainGroup: "com.microsoft.adalcache"
            )
            let authenticator = try DCGAuthenticator(config: config)
            let anchor = try presentationViewController()
            let webParams = MSALWebviewParameters(authPresentationViewController: anchor)
            let token = try await authenticator.token(scopes: scopes, webviewParameters: webParams)
            return token.username ?? token.accountIdentifier ?? "Signed in"
        }
    }

    /// MSAL on macOS presents `ASWebAuthenticationSession` from a view
    /// controller's window. Use the key/main window's content view controller,
    /// falling back to a transient controller wrapping its content view.
    private static func presentationViewController() throws -> NSViewController {
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
        guard let window else { throw ConfigError.noPresentationAnchor }
        if let vc = window.contentViewController {
            return vc
        }
        let vc = NSViewController()
        vc.view = window.contentView ?? NSView()
        return vc
    }
}
#endif
