// MirroringView — the direct screen-mirroring screen: enter a peer host/port,
// Connect over QUIC (Nano transport), and watch the live video surface plus a
// received-frame counter. Leave the host empty to run a local loopback
// self-test of the pipeline.
//
// SPDX-License-Identifier: MIT

#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import PhoneLinkVideo

public struct MirroringView: View {
    @ObservedObject private var model: MirroringViewModel
    @State private var host: String = ""
    @State private var portText: String = "5001"

    public init(model: MirroringViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            videoSurface
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(stateLabel).font(.subheadline).bold()
                if !model.statusDetail.isEmpty {
                    Text("\(model.statusDetail) · \(model.framesReceived) frames")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("peer host (empty = self-test)", text: $host)
                .textFieldStyle(.roundedBorder).frame(width: 180)
            TextField("port", text: $portText)
                .textFieldStyle(.roundedBorder).frame(width: 60)
            if model.isActive {
                Button("Disconnect") { model.disconnect() }
            } else {
                Button("Connect") {
                    model.connect(host: host, port: UInt16(portText) ?? 5001)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    private var videoSurface: some View {
        ZStack {
            Color.black
            VideoDisplayView { view in model.controller.displayView = view }
            // Capture cursor/keyboard only while connected, so stray movement
            // never leaks before pairing. Coordinates are letterbox-mapped.
            if model.isActive {
                RemoteInputView(videoSize: model.videoSize) { event in
                    model.sendInput(event)
                }
            }
            if model.framesReceived == 0 {
                VStack(spacing: 6) {
                    Image(systemName: "display").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("No video yet — Connect to a peer to start mirroring.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var dotColor: Color {
        switch model.state {
        case .ready: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .cancelled, .idle: return .gray
        }
    }

    private var stateLabel: String {
        switch model.state {
        case .idle: return "Screen mirroring — idle"
        case .connecting: return "Connecting…"
        case .ready: return "Connected (direct)"
        case .failed(let m): return "Failed: \(m)"
        case .cancelled: return "Disconnected"
        }
    }
}
#endif
