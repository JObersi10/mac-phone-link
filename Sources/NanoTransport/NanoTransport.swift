// NanoTransport — the direct (QUIC) transport abstraction for screen mirroring
// and other high-bandwidth streams.
//
// This is the "Nano" path: once the side channel negotiates a direct connection
// (Wi-Fi Direct / instant hotspot, exchanged via the context_source handshake),
// media flows peer-to-peer over QUIC rather than through the DCG cloud relay.
// The protocol here is intentionally transport-agnostic so it can be driven by
// a QUIC connection in production and a mock in tests.
//
// SPDX-License-Identifier: MIT

import Foundation

public enum NanoConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case ready
    case failed(String)
    case cancelled
}

/// A bidirectional, message-framed transport. Implementations frame each
/// `send` payload with `NanoFraming` and deliver whole frames to `onFrame`.
public protocol NanoTransport: AnyObject {
    var state: NanoConnectionState { get }
    var onFrame: ((Data) -> Void)? { get set }
    var onStateChange: ((NanoConnectionState) -> Void)? { get set }

    func start()
    /// Send one application message (framed by the implementation).
    func send(_ payload: Data)
    func cancel()
}

/// An in-memory loopback transport for tests and local wiring: whatever you
/// `send` is framed, decoded, and delivered back through `onFrame`, exercising
/// the framing path without a network.
public final class LoopbackNanoTransport: NanoTransport {
    public private(set) var state: NanoConnectionState = .idle {
        didSet { onStateChange?(state) }
    }
    public var onFrame: ((Data) -> Void)?
    public var onStateChange: ((NanoConnectionState) -> Void)?

    private var decoder = NanoFrameDecoder()

    public init() {}

    public func start() {
        state = .connecting
        state = .ready
    }

    public func send(_ payload: Data) {
        guard state == .ready else { return }
        do {
            let framed = try NanoFraming.encode(payload)
            for frame in try decoder.push(framed) {
                onFrame?(frame)
            }
        } catch {
            state = .failed(String(describing: error))
        }
    }

    public func cancel() { state = .cancelled }
}
