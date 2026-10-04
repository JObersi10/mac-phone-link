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
    @Environment(\.openWindow) private var openWindow

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
                Button {
                    if let id = model.startFullMirror() { openWindow(id: "app-mirror", value: id) }
                } label: {
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
            TabBar()
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

struct TabBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainTab.allCases) { tab in
                Button { model.selectedTab = tab } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(model.selectedTab == tab
                                    ? Color.accentColor.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.selectedTab == tab ? Color.accentColor : Color.primary)
            }
            Spacer()
        }
        .padding(10)
    }
}

struct PhoneScreenTab: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(model.fullScreenSession == nil ? "Phone Screen" : "Phone screen is open")
                .font(.title3)
            Text("The phone screen opens in its own window — like each app.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(model.fullScreenSession == nil ? "Open Phone Screen" : "Focus Phone Screen") {
                if let id = model.startFullMirror() { openWindow(id: "app-mirror", value: id) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct AppsTab: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.installedApps.isEmpty ? "Apps" : "\(model.installedApps.count) apps")
                    .foregroundStyle(.secondary).font(.callout)
                Spacer()
                if model.loadingApps { ProgressView().controlSize(.small) }
                Button { model.refreshApps() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            .padding(10)
            Divider()
            if model.installedApps.isEmpty {
                ComingSoonView(
                    icon: "square.grid.2x2",
                    title: model.loadingApps ? "Loading apps…" : "No apps yet",
                    detail: model.devices.isEmpty
                        ? "Connect your phone to see its apps here."
                        : "Tap Refresh to load your phone's apps.")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.installedApps, id: \.self) { pkg in
                            AppIconButton(package: pkg) { open(pkg) }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func open(_ pkg: String) {
        if let id = model.openApp(pkg) {
            openWindow(id: "app-mirror", value: id)
        }
    }
}

/// A launcher tile for one phone app. Opens the app in its own window.
struct AppIconButton: View {
    @EnvironmentObject var model: AppModel
    let package: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "app.dashed").font(.system(size: 26)).foregroundStyle(.tint))
                Text(model.prettyName(package)).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(package)
    }
}

/// Contents of a dedicated per-app window (opened via `openWindow`).
struct AppMirrorWindow: View {
    @EnvironmentObject var model: AppModel
    let sessionID: UUID?

    var body: some View {
        Group {
            if let id = sessionID, let box = model.session(id: id) {
                MirrorContainer(box: box)
                    .navigationTitle(box.title)
                    .onDisappear { model.close(box) }
            } else {
                Text("This app window is closed.").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 320, minHeight: 520)
    }
}

// MARK: - Mirror embedding

struct MirrorContainer: View {
    @ObservedObject var box: SessionBox

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                MirrorRepresentable(renderView: box.renderView)
                if box.state != .streaming {
                    ProgressView(statusText).tint(.white).foregroundStyle(.white)
                }
            }
            NavButtonBar(box: box)
        }
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

/// Android soft-key bar (back / home / recents) under the mirror.
struct NavButtonBar: View {
    @ObservedObject var box: SessionBox

    var body: some View {
        HStack(spacing: 48) {
            Button { box.press(.back) } label: { Image(systemName: "arrowtriangle.left.fill") }
                .help("Back")
            Button { box.press(.home) } label: { Image(systemName: "circle") }
                .help("Home")
            Button { box.press(.recents) } label: { Image(systemName: "square") }
                .help("Recents")
        }
        .buttonStyle(.plain)
        .font(.system(size: 15))
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
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
