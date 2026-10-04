import SwiftUI
import AppKit
import Companion

// MARK: - Window shell

struct MainWindowView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
        } detail: {
            DetailView()
        }
        .onAppear { model.refreshDevices() }
        .alert("Something went wrong",
               isPresented: Binding(get: { model.lastError != nil },
                                    set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

// MARK: - Sidebar (device + quick actions + media + notifications)

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            Section("Device") {
                DeviceHeaderView()
                if model.devices.count > 1 {
                    Picker("Target device", selection: Binding(
                        get: { model.selectedDevice ?? "" },
                        set: { model.selectedDevice = $0.isEmpty ? nil : $0 })) {
                        ForEach(model.devices, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Quick Actions") {
                Button { model.startFullMirror() } label: {
                    Label("Mirror Phone Screen", systemImage: "iphone")
                }
                Button { model.ringPhone() } label: {
                    Label("Ring My Phone", systemImage: "bell.badge")
                }
            }

            Section("Now Playing") {
                if let media = model.nowPlaying {
                    MediaCardView(media: media)
                } else {
                    Text("Nothing playing").foregroundStyle(.secondary).font(.callout)
                }
            }

            Section("Notifications") {
                if model.notifications.isEmpty {
                    Text("No notifications").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(model.notifications, id: \.id) { n in
                        NotificationRowView(notification: n)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct DeviceHeaderView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone.gen3").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.devices.first ?? "No device")
                    .font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(model.adbReady && !model.devices.isEmpty ? .green : .secondary)
                        .frame(width: 7, height: 7)
                    Text(model.devices.isEmpty ? "Disconnected" : "Connected (adb)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let b = model.battery {
                        Text("· \(b.currentCharge)%").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button { model.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct MediaCardView: View {
    @EnvironmentObject var model: AppModel
    let media: MprisBody

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(media.title ?? "Unknown").font(.callout).bold().lineLimit(1)
            Text(media.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 18) {
                Button { model.mediaCommand("Previous") } label: { Image(systemName: "backward.fill") }
                Button { model.mediaCommand("PlayPause") } label: {
                    Image(systemName: (media.isPlaying ?? false) ? "pause.fill" : "play.fill")
                }
                Button { model.mediaCommand("Next") } label: { Image(systemName: "forward.fill") }
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }
}

struct NotificationRowView: View {
    @EnvironmentObject var model: AppModel
    let notification: NotificationBody

    var body: some View {
        Button {
            // "Click a notification → mirror that app". appName→package
            // resolution is a TODO; for now this opens the app launcher tab.
            model.selectedTab = .apps
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.appName ?? "App").font(.caption).foregroundStyle(.secondary)
                Text(notification.title ?? "").font(.callout).bold().lineLimit(1)
                if let text = notification.text {
                    Text(text).font(.caption).lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

// MARK: - Detail (tabs)

struct DetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.selectedTab) {
                ForEach(MainTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()
            tabContent
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch model.selectedTab {
        case .phone: PhoneScreenTab()
        case .apps: AppsTab()
        case .messages:
            ComingSoonView(icon: "message", title: "Messages",
                           detail: "SMS/MMS threads arrive with the companion transport.")
        case .calls:
            ComingSoonView(icon: "phone", title: "Calls",
                           detail: "Call events and audio routing arrive with the companion transport.")
        case .photos:
            ComingSoonView(icon: "photo.on.rectangle", title: "Photos",
                           detail: "Recent photos browsing arrives with the companion transport.")
        }
    }
}

struct PhoneScreenTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let box = model.fullScreenSession {
            MirrorContainer(box: box)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "iphone").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("Not mirroring").font(.title3)
                Text("Mirroring needs a connected phone with USB (or wireless) debugging.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Start Mirroring") { model.startFullMirror() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

struct AppsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var package = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Android package, e.g. org.videolan.vlc", text: $package)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { launch() }
                Button("Open in Window") { launch() }
                    .disabled(package.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
            Divider()
            if model.appSessions.isEmpty {
                ComingSoonView(icon: "square.grid.2x2",
                               title: "No app windows open",
                               detail: "Each app opens on its own virtual display, so your phone stays free.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.appSessions) { box in
                            AppWindowCard(box: box)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func launch() {
        model.openApp(package)
        package = ""
    }
}

struct AppWindowCard: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var box: SessionBox

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(box.title).font(.headline).lineLimit(1)
                Spacer()
                Button { model.close(box) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
            }
            MirrorContainer(box: box)
                .frame(height: 360)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
    }
}

// MARK: - Mirror embedding

struct MirrorContainer: View {
    @ObservedObject var box: SessionBox

    var body: some View {
        ZStack {
            Color.black
            MirrorRepresentable(renderView: box.renderView)
            if box.state != .streaming {
                ProgressView(statusText).tint(.white).foregroundStyle(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        switch box.state {
        case .connecting: return "Connecting…"
        case .streaming: return ""
        case .stopped: return "Stopped"
        case .failed(let m): return "Error: \(m)"
        case .idle: return "Starting…"
        }
    }
}

/// Bridges the AppKit `InteractiveFrameView` (decode target + input source)
/// into SwiftUI. The view is owned by the SessionBox so it is stable across
/// SwiftUI updates.
struct MirrorRepresentable: NSViewRepresentable {
    let renderView: InteractiveFrameView
    func makeNSView(context: Context) -> InteractiveFrameView { renderView }
    func updateNSView(_ nsView: InteractiveFrameView, context: Context) {}
}

// MARK: - Shared empty state

struct ComingSoonView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(.secondary)
            Text(title).font(.title3)
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
