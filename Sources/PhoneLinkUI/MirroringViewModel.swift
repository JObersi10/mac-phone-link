// MirroringViewModel — drives the direct (Nano/QUIC) screen-mirroring path from
// the UI: a connect/disconnect action, live transport state, a received-frame
// counter, and the bridge that feeds frames into the VideoToolbox pipeline.
//
// SPDX-License-Identifier: MIT

import Foundation
import Combine
import NanoTransport
import PhoneLinkVideo
import PhoneLinkProtos
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
public final class MirroringViewModel: ObservableObject {
    @Published public private(set) var state: NanoConnectionState = .idle
    @Published public private(set) var framesReceived: Int = 0
    @Published public var statusDetail: String = ""

    /// The decode/render pipeline. Attach a display view to `controller`.
    public let controller: VideoStreamController

    #if canImport(CoreGraphics)
    /// Dimensions of the incoming video, used to map cursor → phone coordinates.
    /// Defaults to a portrait phone aspect until the real stream reports its size.
    @Published public var videoSize: CGSize = CGSize(width: 1080, height: 2400)
    #endif

    private var transport: NanoTransport?

    /// Injectable so tests (and a no-peer demo) can supply a transport. The
    /// default opens a real QUIC connection to `host:port`.
    public let transportFactory: (_ host: String, _ port: UInt16) -> NanoTransport

    public init(codec: VideoCodec = .h264,
                transportFactory: ((_ host: String, _ port: UInt16) -> NanoTransport)? = nil) {
        self.controller = VideoStreamController(codec: codec)
        self.transportFactory = transportFactory ?? { host, port in
            #if canImport(Network)
            if #available(macOS 12.0, *) {
                return QUICNanoConnection(config: QUICNanoConfig(host: host, port: port))
            }
            #endif
            return LoopbackNanoTransport()
        }
    }

    /// Connect to a peer. With an empty host, run a local loopback self-test so
    /// the pipeline is exercised without a phone present.
    public func connect(host: String, port: UInt16) {
        disconnect()
        #if canImport(CoreGraphics)
        // Track the real stream resolution for accurate cursor mapping.
        controller.onDimensions = { [weak self] d in
            Task { @MainActor in self?.videoSize = CGSize(width: d.width, height: d.height) }
        }
        #endif
        let isDemo = host.trimmingCharacters(in: .whitespaces).isEmpty
        let t: NanoTransport = isDemo ? LoopbackNanoTransport() : transportFactory(host, port)
        transport = t
        statusDetail = isDemo ? "Local loopback self-test" : "QUIC → \(host):\(port)"

        t.onStateChange = { [weak self] newState in
            Task { @MainActor in self?.state = newState }
        }
        t.onFrame = { [weak self] data in
            Task { @MainActor in
                self?.framesReceived += 1
                // Decode/enqueue; non-video bytes (e.g. the loopback self-test)
                // simply won't produce a sample — the counter still advances.
                _ = try? self?.controller.feed(frame: data)
            }
        }
        t.start()

        if isDemo {
            // Push a frame through the loopback so state/counter visibly move.
            t.send(Data("maclink-nano-selftest".utf8))
        }
    }

    public func disconnect() {
        transport?.cancel()
        transport = nil
        state = .idle
        statusDetail = ""
    }

    /// Send one input event to the phone (framed over the transport). No-op when
    /// not connected, so stray cursor movement never leaks before pairing.
    public func sendInput(_ event: Maclink_Mirroring_V1_InputEventMessage) {
        guard isActive, let t = transport, let data = try? event.serializedData() else { return }
        t.send(data)
    }

    public var isActive: Bool {
        if case .ready = state { return true } else { return false }
    }
}
