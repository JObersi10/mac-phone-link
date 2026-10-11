// AppRootView — shows onboarding until it's complete, then the main window.
//
// SPDX-License-Identifier: MIT

#if canImport(SwiftUI)
import SwiftUI

public struct AppRootView: View {
    @AppStorage("didCompleteOnboarding") private var didOnboard = false
    @ObservedObject private var connection: ConnectionViewModel
    @ObservedObject private var onboarding: OnboardingViewModel

    public init(connection: ConnectionViewModel, onboarding: OnboardingViewModel) {
        self.connection = connection
        self.onboarding = onboarding
    }

    public var body: some View {
        Group {
            if didOnboard {
                PhoneLinkRootView(viewModel: connection)
            } else {
                OnboardingView(model: onboarding)
                    .onChange(of: onboarding.step) { step in
                        if step == .done { didOnboard = true }
                    }
            }
        }
    }
}
#endif
