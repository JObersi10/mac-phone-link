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
    @StateObject private var onboarding = OnboardingViewModel(
        permissions: PermissionsManager(),
        // Placeholder pairing payload until the real DCG pairing handshake is wired.
        pairingPayload: "ms-phone-link://pair?v=1"
    )

    var body: some Scene {
        WindowGroup("Phone Link") {
            AppRootView(connection: connection, onboarding: onboarding)
                .frame(minWidth: 460, minHeight: 520)
        }
    }
}
#endif
