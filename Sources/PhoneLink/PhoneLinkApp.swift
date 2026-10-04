import SwiftUI

@main
struct PhoneLinkApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("mac-phone-link") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Ring My Phone") { model.ringPhone() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

/// Shows onboarding on first run, otherwise the main window.
struct RootView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some View {
        if onboardingDone {
            MainWindowView()
        } else {
            OnboardingView(done: $onboardingDone)
        }
    }
}
