// DCGConnection — transport-agnostic routing on top of the DCG framing.
//
// Composes a `DCGChannel` (the byte pipe — e.g. SignalR) with a `DCGFragmenter`
// and `DCGReassembler`: outgoing payloads are fragmented and written as
// serialized DcgFragmentMessages; incoming frames are parsed, reassembled, and
// surfaced as whole payloads, with acks emitted automatically.
//
// This type has no transport dependency, so it is unit-testable against a mock
// channel (see Tests/).
//
// SPDX-License-Identifier: MIT

import Foundation
import PhoneLinkProtos

/// The minimal byte pipe DCGConnection needs. SignalR is one implementation;
/// a mock is another (tests). Implementations must deliver received frames via
/// `onReceive` and may report lifecycle via `onStateChange`.
public protocol DCGChannel: AnyObject {
    var onReceive: ((Data) -> Void)? { get set }
    var onStateChange: ((DCGChannelState) -> Void)? { get set }
    func start()
    func stop()
    /// Send one already-serialized DCG frame.
    func send(_ frame: Data, completion: @escaping (Error?) -> Void)
}

public enum DCGChannelState: Equatable {
    case connecting
    case connected
    case disconnected(reason: String?)
}

public final class DCGConnection {
    private let channel: DCGChannel
    private let fragmenter: DCGFragmenter
    private let reassembler = DCGReassembler()
    private let sessionID: String
    private var nextMessageID: Int32 = 1
    private var nextSequence: Int32 = 1

    /// Emitted when a complete application payload has been reassembled.
    public var onPayload: ((DCGReassembler.Completed) -> Void)?
    /// Emitted on channel lifecycle changes.
    public var onStateChange: ((DCGChannelState) -> Void)?
    /// If true (default), an ack frame is sent for each received fragment.
    public var autoAck: Bool = true

    public init(channel: DCGChannel, sessionID: String,
                maxFragmentBytes: Int = DCGFraming.defaultMaxFragmentBytes) {
        self.channel = channel
        self.sessionID = sessionID
        self.fragmenter = DCGFragmenter(sessionID: sessionID, maxFragmentBytes: maxFragmentBytes)
        self.channel.onReceive = { [weak self] data in self?.handleIncoming(data) }
        self.channel.onStateChange = { [weak self] state in self?.onStateChange?(state) }
    }

    public func start() { channel.start() }
    public func stop() { channel.stop() }

    /// Fragment and send an application payload. Returns the messageID used.
    @discardableResult
    public func send(
        payload: Data,
        handlerType: String,
        messageType: Maclink_Platform_V1_TransportMessageType = .app,
        completion: ((Error?) -> Void)? = nil
    ) throws -> Int32 {
        let messageID = nextMessageID
        nextMessageID &+= 1
        let fragments = try fragmenter.fragment(
            payload: payload,
            messageID: messageID,
            startingSequenceNumber: nextSequence,
            handlerType: handlerType,
            messageType: messageType
        )
        nextSequence &+= Int32(fragments.count)

        var remaining = fragments.count
        var firstError: Error?
        for frag in fragments {
            let bytes = try frag.serializedData()
            channel.send(bytes) { error in
                if let error, firstError == nil { firstError = error }
                remaining -= 1
                if remaining == 0 { completion?(firstError) }
            }
        }
        return messageID
    }

    // MARK: Incoming

    private func handleIncoming(_ data: Data) {
        guard let frag = try? Maclink_Platform_V1_DcgFragmentMessage(serializedBytes: data) else {
            return  // Not a fragment frame (could be an ack/presence); ignored here.
        }
        if autoAck {
            let ack = DCGAck.make(
                sessionID: sessionID,
                sequenceNumber: frag.sequenceNumber,
                handlerType: frag.handlerType,
                success: true
            )
            if let ackBytes = try? ack.serializedData() {
                channel.send(ackBytes) { _ in }
            }
        }
        if let completed = try? reassembler.accept(frag) {
            onPayload?(completed)
        }
    }
}
