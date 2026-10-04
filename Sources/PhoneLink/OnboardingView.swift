import SwiftUI

/// First-run onboarding. Honest about what each transport needs: the companion
/// features need no debugging; mirroring needs adb (USB cable or wireless
/// debugging).
struct OnboardingView: View {
    @Binding var done: Bool
    @EnvironmentObject var model: AppModel
    @State private var step = 0

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            content
                .frame(maxWidth: 520)
            Spacer()
            controls
        }
        .padding(40)
        .onAppear { model.refreshDevices() }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            stepView(
                icon: "iphone.gen3",
                title: "Welcome to mac-phone-link",
                body: "Your Android phone on your Mac — screen mirroring, per-app windows, "
                    + "notifications, media, ring, and battery. No Microsoft account, no cloud."
            )
        case 1:
            VStack(spacing: 16) {
                stepView(
                    icon: "cable.connector",
                    title: "Connect your phone (for mirroring)",
                    body: "Screen mirroring needs adb — a USB cable with USB debugging enabled "
                        + "is the simplest and works fully offline. Wireless debugging also works "
                        + "if both devices share Wi-Fi. (The companion features below need neither.)"
                )
                GroupBox {
                    HStack {
                        Image(systemName: model.adbReady && !model.devices.isEmpty
                              ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(model.adbReady && !model.devices.isEmpty ? .green : .orange)
                        Text(deviceStatusText).font(.callout)
                        Spacer()
                        Button("Refresh") { model.refreshDevices() }
                    }
                    .padding(6)
                }
            }
        case 2:
            stepView(
                icon: "bell.badge",
                title: "Companion features",
                body: "Notifications, media controls, ring-my-phone and battery run over a "
                    + "separate low-bandwidth channel and need NO debugging. The companion app "
                    + "and its Bluetooth/Wi-Fi transport are the next milestone — this step will "
                    + "pair your phone once that ships."
            )
        default:
            stepView(
                icon: "checkmark.seal",
                title: "You're set",
                body: "Use the sidebar to mirror your screen or open an app in its own window. "
                    + "Companion features light up when the transport milestone lands."
            )
        }
    }

    private var deviceStatusText: String {
        if !model.adbReady { return "adb not available yet" }
        if model.devices.isEmpty { return "No device detected — plug in and allow USB debugging" }
        return "Detected: \(model.devices.joined(separator: ", "))"
    }

    private func stepView(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.tint)
            Text(title).font(.title2).bold()
            Text(body).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack {
            if step > 0 { Button("Back") { step -= 1 } }
            Spacer()
            PageDots(count: lastStep + 1, index: step)
            Spacer()
            Button(step == lastStep ? "Get Started" : "Next") {
                if step == lastStep { done = true } else { step += 1 }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(i == index ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}
