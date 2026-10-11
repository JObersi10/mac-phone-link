// MessagingClient — send SMS/RCS messages from the Mac and observe the result.
//
// A FeatureHandler over the "messaging" channel: encodes a SendMessageRequest
// and decodes SendMessageResponse into observable state. Transport-agnostic;
// attach it to a FeatureHub.
//
// SPDX-License-Identifier: MIT

import Foundation
import Combine
import PhoneLinkProtos

@MainActor
public final class MessagingClient: ObservableObject, FeatureHandler {
    public let handlerType = "messaging"

    public enum SendState: Equatable {
        case idle, sending
        case sent(messageID: String)
        case failed(String)
    }

    @Published public private(set) var sendState: SendState = .idle

    private var send: ((Data) -> Void)?

    public init() {}

    public func bindSend(_ send: @escaping (Data) -> Void) { self.send = send }

    /// Compose and send a message. `recipients` are phone numbers / addresses.
    public func sendMessage(to recipients: [String], body: String, threadID: Int64 = 0) {
        let cleaned = recipients.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty, !body.isEmpty, let send else {
            sendState = .failed("No recipients, empty body, or not connected.")
            return
        }
        var req = Maclink_Messaging_V1_SendMessageRequestMessage()
        req.recipients = cleaned
        req.body = body
        req.threadID = threadID
        guard let data = try? req.serializedData() else {
            sendState = .failed("Failed to encode message."); return
        }
        sendState = .sending
        send(data)
    }

    public func handleIncoming(_ payload: Data) {
        guard let resp = try? Maclink_Messaging_V1_SendMessageResponseMessage(serializedBytes: payload) else { return }
        switch resp.status {
        case .ok:
            sendState = .sent(messageID: resp.messageID)
        default:
            let detail = resp.errorDetail.isEmpty ? String(describing: resp.status) : resp.errorDetail
            sendState = .failed(detail)
        }
    }
}
