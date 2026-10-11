// DCGFraming — fragmentation / reassembly for the Device Connectivity Gateway
// message framing (DcgFragmentMessage / DcgAckMessage / DcgBaseMessage).
//
// An application payload is split into N fragments that share a `messageID`,
// ordered by `fragmentID` (0..<fragmentCount), each carrying a slice in `raw`.
// The receiver buffers fragments per messageID and concatenates once all are
// present. Acks are keyed on `sequenceNumber`.
//
// This file is pure Swift over the generated protobuf models — no transport
// dependency — so it is unit-testable in isolation (see Tests/).
//
// SPDX-License-Identifier: MIT

import Foundation
import PhoneLinkProtos

public enum DCGFraming {
    /// Protocol version echoed in each base message (observed as a double field).
    public static let protocolVersion: Double = 1.0
    /// Default maximum bytes of application payload carried per fragment.
    public static let defaultMaxFragmentBytes = 60 * 1024
}

public enum DCGFramingError: Error, Equatable {
    case emptyPayload
    case fragmentCountMismatch(expected: Int, got: Int)
    case duplicateFragment(messageID: Int32, fragmentID: Int32)
    case fragmentIndexOutOfRange(fragmentID: Int32, fragmentCount: Int32)
}

// MARK: - Fragmenter

public struct DCGFragmenter {
    public var sessionID: String
    public var maxFragmentBytes: Int

    public init(sessionID: String, maxFragmentBytes: Int = DCGFraming.defaultMaxFragmentBytes) {
        precondition(maxFragmentBytes > 0, "maxFragmentBytes must be positive")
        self.sessionID = sessionID
        self.maxFragmentBytes = maxFragmentBytes
    }

    private func makeBase() -> Maclink_Platform_V1_DcgBaseMessage {
        var base = Maclink_Platform_V1_DcgBaseMessage()
        base.version = DCGFraming.protocolVersion
        base.type = .fragment
        base.sessionID = sessionID
        return base
    }

    /// Split an application payload into ordered DCG fragment messages.
    public func fragment(
        payload: Data,
        messageID: Int32,
        startingSequenceNumber: Int32,
        handlerType: String,
        messageType: Maclink_Platform_V1_TransportMessageType = .app
    ) throws -> [Maclink_Platform_V1_DcgFragmentMessage] {
        guard !payload.isEmpty else { throw DCGFramingError.emptyPayload }

        // Ceil-divide into chunks.
        let count = (payload.count + maxFragmentBytes - 1) / maxFragmentBytes
        var fragments: [Maclink_Platform_V1_DcgFragmentMessage] = []
        fragments.reserveCapacity(count)

        for index in 0..<count {
            let lo = index * maxFragmentBytes
            let hi = min(lo + maxFragmentBytes, payload.count)
            let slice = payload.subdata(in: lo..<hi)

            var frag = Maclink_Platform_V1_DcgFragmentMessage()
            frag.base = makeBase()
            frag.sequenceNumber = startingSequenceNumber + Int32(index)
            frag.messageID = messageID
            frag.fragmentID = Int32(index)
            frag.fragmentCount = Int32(count)
            frag.messageType = messageType
            frag.handlerType = handlerType
            frag.raw = slice
            fragments.append(frag)
        }
        return fragments
    }
}

// MARK: - Reassembler

/// Buffers incoming fragments per messageID and yields the complete payload
/// once every fragment has arrived. Not thread-safe; confine to one queue.
public final class DCGReassembler {
    private struct Buffer {
        let fragmentCount: Int32
        var chunks: [Int32: Data] = [:]
        var handlerType: String
        var messageType: Maclink_Platform_V1_TransportMessageType
    }

    private var buffers: [Int32: Buffer] = [:]

    public init() {}

    public struct Completed {
        public let messageID: Int32
        public let handlerType: String
        public let messageType: Maclink_Platform_V1_TransportMessageType
        public let payload: Data
    }

    /// Accept one fragment. Returns a `Completed` payload when the fragment set
    /// for its messageID is now whole, otherwise nil.
    @discardableResult
    public func accept(_ frag: Maclink_Platform_V1_DcgFragmentMessage) throws -> Completed? {
        let count = frag.fragmentCount
        guard frag.fragmentID >= 0 && frag.fragmentID < count else {
            throw DCGFramingError.fragmentIndexOutOfRange(fragmentID: frag.fragmentID, fragmentCount: count)
        }

        var buffer = buffers[frag.messageID]
            ?? Buffer(fragmentCount: count, handlerType: frag.handlerType, messageType: frag.messageType)

        guard buffer.fragmentCount == count else {
            throw DCGFramingError.fragmentCountMismatch(expected: Int(buffer.fragmentCount), got: Int(count))
        }
        guard buffer.chunks[frag.fragmentID] == nil else {
            throw DCGFramingError.duplicateFragment(messageID: frag.messageID, fragmentID: frag.fragmentID)
        }

        buffer.chunks[frag.fragmentID] = frag.raw
        buffers[frag.messageID] = buffer

        guard Int32(buffer.chunks.count) == count else { return nil }

        var payload = Data()
        for i in 0..<count {
            payload.append(buffer.chunks[i] ?? Data())
        }
        buffers.removeValue(forKey: frag.messageID)
        return Completed(
            messageID: frag.messageID,
            handlerType: buffer.handlerType,
            messageType: buffer.messageType,
            payload: payload
        )
    }

    /// Number of partially-received messages still buffered.
    public var pendingCount: Int { buffers.count }

    public func reset() { buffers.removeAll() }
}

// MARK: - Acks

public enum DCGAck {
    /// Build an acknowledgement for a received fragment's sequence number.
    public static func make(
        sessionID: String,
        sequenceNumber: Int32,
        handlerType: String,
        success: Bool,
        errorNumber: Int32 = 0,
        errorMessage: String? = nil
    ) -> Maclink_Platform_V1_DcgAckMessage {
        var base = Maclink_Platform_V1_DcgBaseMessage()
        base.version = DCGFraming.protocolVersion
        base.type = .acknowledgement
        base.sessionID = sessionID

        var ack = Maclink_Platform_V1_DcgAckMessage()
        ack.base = base
        ack.sequenceNumber = sequenceNumber
        ack.handlerType = handlerType
        ack.success = success
        ack.errorNo = errorNumber
        if let errorMessage { ack.errorMessage = errorMessage }
        return ack
    }
}
