// FeatureChannel — the backbone that attaches feature handlers (clipboard,
// messaging, contacts, …) to a live byte channel.
//
// A `FeatureTransport` carries opaque payloads tagged by a handler-type string
// (the same routing key DCGConnection already uses). A `FeatureHub` registers
// handlers, routes inbound payloads to the matching one, and gives each handler
// a `send` closure that tags outbound payloads with its type. This is the seam
// a real transport (Nano/QUIC or DCG) plugs into; `LoopbackFeatureTransport`
// stands in for tests and local wiring.
//
// SPDX-License-Identifier: MIT

import Foundation

/// A transport that sends/receives payloads tagged by handler type.
public protocol FeatureTransport: AnyObject {
    var onPayload: ((_ handlerType: String, _ payload: Data) -> Void)? { get set }
    func send(handlerType: String, _ payload: Data)
}

/// An in-memory transport: a `send` is delivered straight back through
/// `onPayload`, so a hub + handlers can be exercised without a network.
public final class LoopbackFeatureTransport: FeatureTransport {
    public var onPayload: ((String, Data) -> Void)?
    public init() {}
    public func send(handlerType: String, _ payload: Data) {
        onPayload?(handlerType, payload)
    }
}

/// A feature that speaks one handler type over the channel.
@MainActor
public protocol FeatureHandler: AnyObject {
    var handlerType: String { get }
    /// Called with an inbound payload addressed to this handler.
    func handleIncoming(_ payload: Data)
    /// The hub injects the closure this handler uses to send outbound payloads.
    func bindSend(_ send: @escaping (Data) -> Void)
}

@MainActor
public final class FeatureHub {
    private let transport: FeatureTransport
    private var handlers: [String: FeatureHandler] = [:]

    public init(transport: FeatureTransport) {
        self.transport = transport
        transport.onPayload = { [weak self] type, data in
            Task { @MainActor in self?.handlers[type]?.handleIncoming(data) }
        }
    }

    /// Register a handler and wire its outbound sends through the transport.
    public func register(_ handler: FeatureHandler) {
        handlers[handler.handlerType] = handler
        let type = handler.handlerType
        handler.bindSend { [weak transport] data in transport?.send(handlerType: type, data) }
    }

    public func handler(for type: String) -> FeatureHandler? { handlers[type] }
}
