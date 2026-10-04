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
                Button("Check for Updates…") { UpdateChecker.shared.checkAndPresent() }
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

        // Each phone app opens in its own window (opened via openWindow).
        WindowGroup(id: "app-mirror", for: UUID.self) { $sessionID in
            AppMirrorWindow(sessionID: sessionID)
                .environmentObject(model)
        }

        // Menu-bar icon with quick actions (always present, even when the main
        // window is closed).
        MenuBarExtra("mac-phone-link", systemImage: "iphone") {
            MenuBarContent().environmentObject(model)
        }
    }
}

/// Contents of the menu-bar dropdown. In its own view so it can use
/// `openWindow` (phone screen opens in its own window, like apps).
struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Mirror Phone Screen") {
            if let id = model.startFullMirror() { openWindow(id: "app-mirror", value: id) }
        }
        Button("Ring My Phone") { model.ringPhone() }
        Divider()
        Button("Check for Updates…") { UpdateChecker.shared.checkAndPresent() }
        Button("Save Log to Downloads") {
            if let url = try? AppLog.shared.saveToDownloads() {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        Divider()
        Button("Quit mac-phone-link") { NSApplication.shared.terminate(nil) }
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
