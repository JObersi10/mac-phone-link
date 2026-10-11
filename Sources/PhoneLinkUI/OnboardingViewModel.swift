// OnboardingViewModel — drives the first-run flow: permissions → Microsoft
// sign-in → QR pairing. Sign-in is injected (so PhoneLinkUI stays decoupled
// from MSAL UI); wire it to DCGAuthenticator in the app.
//
// SPDX-License-Identifier: MIT

import Foundation
import Combine

@MainActor
public final class OnboardingViewModel: ObservableObject {
    public enum Step: Int, CaseIterable {
        case welcome, permissions, signIn, pairing, done
        public var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .permissions: return "Permissions"
            case .signIn: return "Sign in"
            case .pairing: return "Pair your phone"
            case .done: return "All set"
            }
        }
    }

    @Published public private(set) var step: Step = .welcome
    @Published public var signedInUser: String?
    @Published public var isSigningIn = false
    @Published public var signInError: String?
    /// The payload encoded into the pairing QR (set by the app once known).
    @Published public var pairingPayload: String

    public let permissions: PermissionsManager

    /// Injected Microsoft sign-in; returns the signed-in account's display name.
    public var signInAction: (() async throws -> String)?

    /// Called once the flow reaches `.done`.
    public var onFinish: (() -> Void)?

    public init(permissions: PermissionsManager, pairingPayload: String = "") {
        self.permissions = permissions
        self.pairingPayload = pairingPayload
    }

    public var isSignedIn: Bool { signedInUser != nil }

    public func next() {
        let all = Step.allCases
        guard let idx = all.firstIndex(of: step), idx + 1 < all.count else { return }
        step = all[idx + 1]
        if step == .done { onFinish?() }
    }

    public func back() {
        let all = Step.allCases
        guard let idx = all.firstIndex(of: step), idx > 0 else { return }
        step = all[idx - 1]
    }

    public func signIn() async {
        guard let action = signInAction else {
            signInError = "Sign-in not configured (set signInAction / MSAL client id)."
            return
        }
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }
        do {
            signedInUser = try await action()
        } catch {
            signInError = String(describing: error)
        }
    }
}
