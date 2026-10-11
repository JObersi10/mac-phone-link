// PhoneLinkApp — runnable macOS app entry point. Hosts the onboarding/pairing
// flow and main window from PhoneLinkUI.
//
// SPDX-License-Identifier: MIT

#if canImport(SwiftUI)
import SwiftUI
import PhoneLinkUI

@main
struct PhoneLinkApp: App {
    @StateObject private var connection = ConnectionViewModel()
    @StateObject private var onboarding: OnboardingViewModel

    init() {
        let model = OnboardingViewModel(
            permissions: PermissionsManager(),
            // Placeholder pairing payload until the real DCG pairing handshake is wired.
            pairingPayload: "ms-phone-link://pair?v=1"
        )
        // Wire the real Microsoft (MSAL) interactive sign-in. Requires a
        // caller-supplied Entra client id; see MicrosoftSignIn for how it's
        // resolved (env / UserDefaults field / Info.plist).
        #if canImport(MSAL)
        model.signInAction = MicrosoftSignIn.makeSignInAction()
        #endif
        _onboarding = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup("Phone Link") {
            AppRootView(connection: connection, onboarding: onboarding)
                .frame(minWidth: 460, minHeight: 520)
        }
    }
}
#endif
