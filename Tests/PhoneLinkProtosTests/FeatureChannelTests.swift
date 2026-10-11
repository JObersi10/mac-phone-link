// Feature-channel + client encoding tests.
//
// SPDX-License-Identifier: MIT

import XCTest
import PhoneLinkProtos
@testable import PhoneLinkUI

/// Captures what each handler sends, without echoing.
private final class CapturingTransport: FeatureTransport {
    var onPayload: ((String, Data) -> Void)?
    var sent: [(type: String, data: Data)] = []
    func send(handlerType: String, _ payload: Data) { sent.append((handlerType, payload)) }
}

@MainActor
final class FeatureChannelTests: XCTestCase {

    func testMessagingEncodesRequest() throws {
        let t = CapturingTransport()
        let hub = FeatureHub(transport: t)
        let messaging = MessagingClient()
        hub.register(messaging)

        messaging.sendMessage(to: ["+15551234567", " +15557654321 "], body: "hi there")
        XCTAssertEqual(t.sent.count, 1)
        XCTAssertEqual(t.sent[0].type, "messaging")
        let req = try Maclink_Messaging_V1_SendMessageRequestMessage(serializedBytes: t.sent[0].data)
        XCTAssertEqual(req.recipients, ["+15551234567", "+15557654321"])  // trimmed
        XCTAssertEqual(req.body, "hi there")
    }

    func testMessagingRejectsEmpty() {
        let hub = FeatureHub(transport: CapturingTransport())
        let m = MessagingClient()
        hub.register(m)
        m.sendMessage(to: [], body: "x")
        if case .failed = m.sendState {} else { XCTFail("expected failure state") }
    }

    func testMessagingDecodesOkResponse() throws {
        let m = MessagingClient()
        m.bindSend { _ in }
        var resp = Maclink_Messaging_V1_SendMessageResponseMessage()
        resp.status = .ok
        resp.messageID = "mid-42"
        m.handleIncoming(try resp.serializedData())
        XCTAssertEqual(m.sendState, .sent(messageID: "mid-42"))
    }

    func testContactsEncodesSearch() throws {
        let t = CapturingTransport()
        let hub = FeatureHub(transport: t)
        let contacts = ContactsClient()
        hub.register(contacts)

        contacts.search("alice", maxResults: 10)
        XCTAssertEqual(t.sent.first?.type, "contacts")
        let req = try Maclink_Contacts_V1_ContactSearchRequestMessage(serializedBytes: t.sent[0].data)
        XCTAssertEqual(req.query, "alice")
        XCTAssertEqual(req.maxResults, 10)
    }

    func testContactsDecodesResults() throws {
        let c = ContactsClient()
        c.bindSend { _ in }
        var item = Maclink_Contacts_V1_ContactItem()
        item.displayName = "Bob Jones"
        var num = Maclink_Contacts_V1_ContactPhoneNumber()
        num.displayValue = "+1 555 000 1111"
        item.phoneNumbers = [num]
        var resp = Maclink_Contacts_V1_ContactSearchResponseMessage()
        resp.contacts = [item]
        c.handleIncoming(try resp.serializedData())
        XCTAssertEqual(c.results.count, 1)
        XCTAssertEqual(c.results[0].name, "Bob Jones")
        XCTAssertEqual(c.results[0].numbers, ["+1 555 000 1111"])
    }

    func testHubRoutesInboundByType() {
        let t = LoopbackFeatureTransport()
        let hub = FeatureHub(transport: t)
        let m = MessagingClient()
        hub.register(m)
        // Deliver an OK response addressed to "messaging".
        var resp = Maclink_Messaging_V1_SendMessageResponseMessage()
        resp.status = .ok; resp.messageID = "routed"
        t.send(handlerType: "messaging", try! resp.serializedData())
        XCTAssertEqual(m.sendState, .sent(messageID: "routed"))
    }

    func testClipboardCodecTextRoundTrip() {
        let msg = ClipboardCodec.response([ClipboardCodec.textItem("clip me")])
        let data = try! msg.serializedData()
        let parsed = try! Maclink_Clipboard_V1_ResponseMessage(serializedBytes: data)
        XCTAssertEqual(ClipboardCodec.firstText(in: parsed), "clip me")
    }
}
