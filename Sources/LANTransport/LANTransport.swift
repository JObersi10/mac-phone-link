// LANTransport — direct Mac↔phone transport for the own-protocol app (M1).
// Bonjour discovery + a framed TLS/TCP socket over the local network, with no
// cloud, account, or Microsoft dependency. Exposes length-prefixed messages
// that the feature layer / decoder ride on.
//
// The framing (`LengthPrefixFramer`) is pure and unit-tested; the
// Network.framework pieces are thin wrappers around it.
//
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(Network)
import Network
#endif

// MARK: - Framing (pure, testable)

/// 4-byte big-endian length prefix + payload. Accumulates partial reads and
/// yields complete messages.
public struct LengthPrefixFramer {
    private var buffer = Data()
    public init() {}

    /// Frame a payload for sending.
    public static func frame(_ payload: Data) -> Data {
        let n = UInt32(payload.count)
        var out = Data(capacity: 4 + payload.count)
        out.append(UInt8((n >> 24) & 0xFF))
        out.append(UInt8((n >> 16) & 0xFF))
        out.append(UInt8((n >> 8) & 0xFF))
        out.append(UInt8(n & 0xFF))
        out.append(payload)
        return out
    }

    /// Feed received bytes; return any complete payloads now available.
    public mutating func push(_ data: Data) -> [Data] {
        buffer.append(data)
        var messages: [Data] = []
        while buffer.count >= 4 {
            let b = [UInt8](buffer.prefix(4))
            let len = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
            let total = 4 + Int(len)
            guard buffer.count >= total else { break }
            messages.append(buffer.subdata(in: 4..<total))
            buffer.removeSubrange(0..<total)
        }
        return messages
    }
}

public let lanServiceType = "_maclink._tcp"

#if canImport(Network)

// MARK: - Connection

/// A framed message connection over a single NWConnection.
public final class LANConnection: @unchecked Sendable {
    private let connection: NWConnection
    private var framer = LengthPrefixFramer()
    private let queue = DispatchQueue(label: "maclink.lan.conn")

    public var onMessage: (@Sendable (Data) -> Void)?
    public var onState: (@Sendable (NWConnection.State) -> Void)?

    public init(_ connection: NWConnection) {
        self.connection = connection
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onState?(state)
            if case .ready = state { self?.receiveLoop() }
        }
        connection.start(queue: queue)
    }

    public func send(_ payload: Data) {
        connection.send(content: LengthPrefixFramer.frame(payload),
                        completion: .contentProcessed { _ in })
    }

    public func cancel() { connection.cancel() }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                for msg in self.framer.push(data) { self.onMessage?(msg) }
            }
            if isComplete || error != nil { self.connection.cancel(); return }
            self.receiveLoop()
        }
    }
}

// MARK: - Transport (advertise + browse)

public final class LANTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "maclink.lan.transport")
    private var listener: NWListener?
    private var browser: NWBrowser?

    public init() {}

    /// Advertise this device and accept incoming connections.
    public func advertise(name: String,
                          using params: NWParameters = .tls,
                          onConnection: @escaping @Sendable (LANConnection) -> Void) throws {
        let listener = try NWListener(using: params)
        listener.service = NWListener.Service(name: name, type: lanServiceType)
        listener.newConnectionHandler = { conn in onConnection(LANConnection(conn)) }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Browse for peers advertising the service.
    public func browse(onChange: @escaping @Sendable (Set<NWBrowser.Result>) -> Void) {
        let browser = NWBrowser(for: .bonjour(type: lanServiceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in onChange(results) }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// Connect to a discovered peer.
    public func connect(to endpoint: NWEndpoint, using params: NWParameters = .tls) -> LANConnection {
        LANConnection(NWConnection(to: endpoint, using: params))
    }

    public func stop() {
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
    }
}

#endif
