// PhoneLinkApp — runnable macOS app entry point. Hosts the onboarding/pairing
// flow and main window from PhoneLinkUI.
//
// SPDX-License-Identifier: MIT

#if canImport(SwiftUI)
import SwiftUI
import PhoneLinkUI
import PhoneLinkPairing

@main
struct PhoneLinkApp: App {
    @StateObject private var connection = ConnectionViewModel()
    @StateObject private var onboarding: OnboardingViewModel

    init() {
        // Build a QR payload in the real grammar the phone scanner expects: an
        // HTTPS dynamic link to a DCG host with vm/uaid/ti/r/apn. (A bare
        // "uaid=..." string is rejected by the scanner's validateUri — no scheme
        // or host.) Backed by a locally-generated code, NOT a real cloud
        // PinSession yet, so a phone will accept the scan but can't complete the
        // first-party-gated pairing. The QR is now structurally valid.
        let sample = QRPairingPayload(
            pairingCode: Self.randomPairingCode(),
            prefix: "maclink\(UInt32.random(in: 0..<0xFFFFFF))"
        )
        let model = OnboardingViewModel(
            permissions: PermissionsManager(),
            pairingPayload: sample.encoded()
        )
        // Wire the real Microsoft (MSAL) interactive sign-in. Requires a
        // caller-supplied Entra client id; see MicrosoftSignIn for how it's
        // resolved (env / UserDefaults field / Info.plist).
        #if canImport(MSAL)
        model.signInAction = MicrosoftSignIn.makeSignInAction()
        #endif
        _onboarding = StateObject(wrappedValue: model)
    }

    /// A 16-character pairing code (the slice the phone reads from `uaid`).
    private static func randomPairingCode() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<QRPairingPayload.pairingCodeLength).map { _ in alphabet.randomElement()! })
    }

    var body: some Scene {
        WindowGroup("Phone Link") {
            AppRootView(connection: connection, onboarding: onboarding)
                .frame(minWidth: 460, minHeight: 520)
        }
    }
}
#endif
