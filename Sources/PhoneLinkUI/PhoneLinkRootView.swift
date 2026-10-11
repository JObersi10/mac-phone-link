// PhoneLinkRootView — the macOS window content: a connection-status header and
// a live list of mirrored phone notifications, driven by ConnectionViewModel.
//
// SwiftUI on macOS is AppKit-backed; this draft uses SwiftUI primitives and a
// few AppKit colors. Wire it up by creating a ConnectionViewModel, binding it
// to a started DCGSession's connection, and hosting this view.
//
// SPDX-License-Identifier: MIT

#if canImport(SwiftUI)
import SwiftUI

public struct PhoneLinkRootView: View {
    @ObservedObject private var viewModel: ConnectionViewModel

    public init(viewModel: ConnectionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            StatusHeader(state: viewModel.state,
                         onConnect: viewModel.start,
                         onDisconnect: viewModel.stop)
            Divider()
            if viewModel.notifications.isEmpty {
                EmptyNotificationsView()
            } else {
                NotificationListView(items: viewModel.notifications)
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

struct StatusHeader: View {
    let state: UIConnectionState
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    private var dotColor: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        case .idle: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 10, height: 10)
            Text(state.label).font(.headline)
            Spacer()
            if state.isConnected {
                Button("Disconnect", action: onDisconnect)
            } else {
                Button("Connect", action: onConnect)
            }
        }
        .padding(12)
    }
}

struct EmptyNotificationsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No notifications yet")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct NotificationListView: View {
    let items: [NotificationItem]

    var body: some View {
        List(items) { item in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.appName.isEmpty ? "Phone" : item.appName)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.postTime, style: .time)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !item.title.isEmpty {
                    Text(item.title).font(.body).bold()
                }
                if !item.text.isEmpty {
                    Text(item.text).font(.body).foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
#endif
