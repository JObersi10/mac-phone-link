// OnboardingView — the first-run SwiftUI flow: welcome, permissions, Microsoft
// sign-in, and QR pairing.
//
// SPDX-License-Identifier: MIT

#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

public struct OnboardingView: View {
    @ObservedObject private var model: OnboardingViewModel

    public init(model: OnboardingViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            StepHeader(step: model.step)
            Divider()
            Group {
                switch model.step {
                case .welcome: WelcomeStep()
                case .permissions: PermissionsStep(model: model)
                case .signIn: SignInStep(model: model)
                case .pairing: PairingStep(model: model)
                case .done: DoneStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            Divider()
            NavBar(model: model)
        }
        .frame(minWidth: 460, minHeight: 520)
    }
}

private struct StepHeader: View {
    let step: OnboardingViewModel.Step
    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.gen3").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Connect your phone").font(.title2).bold()
            Text("Mirror your screen and sync notifications, messages and more. "
                 + "A few quick steps to get set up.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
    }
}

private struct PermissionsStep: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allow the permissions this app needs:").font(.headline)
            PermissionRow(title: "Notifications",
                          detail: "Show your phone's notifications on your Mac.",
                          status: model.permissions.notifications) {
                Task { await model.permissions.requestNotifications() }
            }
            PermissionRow(title: "Local Network",
                          detail: "Discover and connect to your phone over Wi-Fi.",
                          status: model.permissions.localNetwork) {
                model.permissions.requestLocalNetwork()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch status {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .denied:
                Label("Denied", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            case .requested:
                ProgressView().controlSize(.small)
            case .unknown:
                Button("Allow", action: action)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

private struct SignInStep: View {
    @ObservedObject var model: OnboardingViewModel
    // Same key MicrosoftSignIn reads in the app layer. Lets a user paste the
    // client id of their own Entra registration without env vars or Info.plist.
    @AppStorage("PhoneLinkMSALClientId") private var clientId = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.badge.key").font(.system(size: 40)).foregroundStyle(.tint)
            Text("Sign in with your Microsoft account").font(.headline)
            if let user = model.signedInUser {
                Label(user, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                VStack(spacing: 6) {
                    TextField("Entra app client id (GUID)", text: $clientId)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                    Text("Register your own Entra app with redirect "
                         + "`msauth.com.maclink.phonelink://auth`, then paste its client id.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                }
                Button {
                    Task { await model.signIn() }
                } label: {
                    if model.isSigningIn { ProgressView().controlSize(.small) }
                    else { Text("Sign in with Microsoft") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSigningIn || clientId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let err = model.signInError {
                Text(err).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
    }
}

private struct PairingStep: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        VStack(spacing: 14) {
            Text("Scan to pair").font(.headline)
            Text("Open the companion app on your phone and scan this code.")
                .font(.caption).foregroundStyle(.secondary)
            if let img = QRCode.image(from: model.pairingPayload) {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable().frame(width: 220, height: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15))
                    .frame(width: 220, height: 220)
                    .overlay(Text("Preparing pairing code…").font(.caption).foregroundStyle(.secondary))
            }
        }
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("You're all set").font(.title2).bold()
            Text("Your phone is linked. You can close this and start mirroring.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

private struct NavBar: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        HStack {
            if model.step != .welcome && model.step != .done {
                Button("Back") { model.back() }
            }
            Spacer()
            Button(model.step == .pairing ? "Finish" : "Continue") { model.next() }
                .buttonStyle(.borderedProminent)
                .disabled(continueDisabled)
        }
        .padding(12)
    }

    private var continueDisabled: Bool {
        switch model.step {
        case .signIn: return !model.isSignedIn
        default: return false
        }
    }
}
#endif
