// NanoHandshake — the context_source identity exchange that opens a Nano
// (direct) connection before media flows.
//
// Order (from the context_source message set): Initialize → IdentityChallenge
// → IdentityResponse → OpenDeviceConnectionRequest → ConnectionInfo. Each is
// wrapped in a ContextSourceMessage (clean-room proto) and sent as one framed
// Nano message. This type only builds/parses those messages; it does not own
// the socket — feed its output to a `NanoTransport.send` and feed received
// frames back in via `handle`.
//
// SPDX-License-Identifier: MIT

import Foundation
import PhoneLinkProtos

public enum NanoHandshakeError: Error, Equatable {
    case unexpectedMessage
    case challengeMismatch
}

public struct NanoHandshake {
    public typealias CSMessage = Maclink_Platform_V1_ContextSourceMessage

    public init() {}

    // MARK: Build (local → peer)

    /// First message: announce this context source.
    public func initialize(contextSourceID: String) -> CSMessage {
        var initMsg = Maclink_Platform_V1_CSInitializeMessage()
        initMsg.contextSourceID = contextSourceID
        var msg = CSMessage()
        msg.type = .csInitializeMessage(initMsg)
        return msg
    }

    /// Answer a peer's identity challenge, echoing its `challenge` and naming
    /// our DCG client id.
    public func identityResponse(to challenge: Maclink_Platform_V1_CSIdentityChallenge,
                                 dcgClientID: String) -> CSMessage {
        var resp = Maclink_Platform_V1_CSIdentityResponse()
        resp.challenge = challenge.challenge
        resp.dcgClientID = dcgClientID
        var msg = CSMessage()
        msg.type = .csIdentityResponse(resp)
        return msg
    }

    /// Request the direct device connection (after identity is established).
    public func openDeviceConnection() -> CSMessage {
        var msg = CSMessage()
        msg.type = .csOpenDeviceConnectionRequest(Maclink_Platform_V1_CSOpenDeviceConnectionRequest())
        return msg
    }

    // MARK: Serialize

    public func serialize(_ message: CSMessage) throws -> Data {
        try message.serializedData()
    }

    public func parse(_ data: Data) throws -> CSMessage {
        try CSMessage(serializedBytes: data)
    }
}
