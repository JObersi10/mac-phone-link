import SwiftUI
import AppKit

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
            CommandMenu("Developer") {
                Button("Save Log to Downloads") {
                    if let url = try? AppLog.shared.saveToDownloads() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Reveal Log Folder in Finder") {
                    if let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
                        .first?.appendingPathComponent("Logs/mac-phone-link") {
                        NSWorkspace.shared.open(dir)
                    }
                }
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
