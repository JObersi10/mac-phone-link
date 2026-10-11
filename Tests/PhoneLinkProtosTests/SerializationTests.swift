// Round-trip serialization tests for the clean-room protobuf models, plus the
// DCG fragmentation/reassembly framing.
//
// SPDX-License-Identifier: MIT

import XCTest
import Foundation
import SwiftProtobuf
@testable import PhoneLinkProtos
@testable import DCGTransport

final class SerializationTests: XCTestCase {

    // MARK: Per-channel round trips (serialize -> parse -> equal)

    func testClipboardRoundTrip() throws {
        var item = Maclink_Clipboard_V1_Item()
        item.itemType = .textPlain
        item.text = "hello 📋 world"
        var msg = Maclink_Clipboard_V1_ResponseMessage()
        msg.status = .ok
        msg.correlationID = "abc-123"
        msg.clipboardItem = [item]

        let data = try msg.serializedData()
        let parsed = try Maclink_Clipboard_V1_ResponseMessage(serializedBytes: data)
        XCTAssertEqual(parsed, msg)
        XCTAssertEqual(parsed.clipboardItem.first?.text, "hello 📋 world")
    }

    func testNotificationRoundTrip() throws {
        var info = Maclink_Notification_V1_NotificationInfo()
        info.key = "k1"
        info.title = "Title"
        info.text = "Body"
        info.appName = "Messages"
        info.packageName = "com.example.app"
        info.postTime = 1_700_000_000_000
        info.isClearable = true
        var resp = Maclink_Notification_V1_ResponseMessage()
        resp.status = .ok
        resp.notifications = [info]

        let data = try resp.serializedData()
        let parsed = try Maclink_Notification_V1_ResponseMessage(serializedBytes: data)
        XCTAssertEqual(parsed, resp)
    }

    func testMessagingRoundTrip() throws {
        var att = Maclink_Messaging_V1_SendMessageAttachment()
        att.name = "pic.jpg"
        att.contentType = "image/jpeg"
        att.data = Data([0xFF, 0xD8, 0xFF, 0xE0])
        var req = Maclink_Messaging_V1_SendMessageRequestMessage()
        req.recipients = ["+15551234567", "+15557654321"]
        req.body = "see attached"
        req.threadID = 42
        req.attachments = [att]

        let data = try req.serializedData()
        let parsed = try Maclink_Messaging_V1_SendMessageRequestMessage(serializedBytes: data)
        XCTAssertEqual(parsed, req)
        XCTAssertEqual(parsed.attachments.first?.data, Data([0xFF, 0xD8, 0xFF, 0xE0]))
    }

    func testContactsRoundTrip() throws {
        var phone = Maclink_Contacts_V1_ContactPhoneNumber()
        phone.type = "mobile"
        phone.value = "+15550000000"
        var contact = Maclink_Contacts_V1_ContactItem()
        contact.id = "c1"
        contact.displayName = "Ada Lovelace"
        contact.phoneNumbers = [phone]
        var resp = Maclink_Contacts_V1_ContactSearchResponseMessage()
        resp.status = .ok
        resp.contacts = [contact]
        resp.hasMore_p = false

        let data = try resp.serializedData()
        let parsed = try Maclink_Contacts_V1_ContactSearchResponseMessage(serializedBytes: data)
        XCTAssertEqual(parsed, resp)
    }

    func testFilesMetadataRoundTrip() throws {
        var meta = Maclink_Files_V1_FileMetadata()
        meta.id = 7
        meta.name = "IMG_0001.HEIC"
        meta.path = "/DCIM/Camera/IMG_0001.HEIC"
        meta.fileType = .image
        meta.size = 2_400_000
        meta.checksum = 0x0BADBEEF
        meta.isDirectory = false

        let data = try meta.serializedData()
        let parsed = try Maclink_Files_V1_FileMetadata(serializedBytes: data)
        XCTAssertEqual(parsed, meta)
    }

    func testSideChannelOneofRoundTrip() throws {
        var req = Maclink_Sidechannel_V1_ClientRequest()
        req.wakeRequest = Maclink_Sidechannel_V1_WakeRequest()
        var auth = Maclink_Sidechannel_V1_Authorization()
        auth.signedJwtPayload = "eyJ.header.sig"
        req.authorization = auth

        let data = try req.serializedData()
        let parsed = try Maclink_Sidechannel_V1_ClientRequest(serializedBytes: data)
        XCTAssertEqual(parsed, req)
        guard case .wakeRequest? = parsed.request else {
            return XCTFail("expected wake_request oneof arm")
        }
        XCTAssertEqual(parsed.authorization.signedJwtPayload, "eyJ.header.sig")
    }

    func testDcgFragmentRoundTrip() throws {
        var base = Maclink_Platform_V1_DcgBaseMessage()
        base.version = 1.0
        base.type = .fragment
        base.sessionID = "sess-1"
        var frag = Maclink_Platform_V1_DcgFragmentMessage()
        frag.base = base
        frag.sequenceNumber = 5
        frag.messageID = 9
        frag.fragmentID = 0
        frag.fragmentCount = 1
        frag.messageType = .app
        frag.handlerType = "clipboard"
        frag.raw = Data([1, 2, 3, 4])

        let data = try frag.serializedData()
        let parsed = try Maclink_Platform_V1_DcgFragmentMessage(serializedBytes: data)
        XCTAssertEqual(parsed, frag)
    }

    // MARK: Fragmentation framing

    func testFragmentReassembleMultiFragment() throws {
        let payload = Data((0..<(130 * 1024)).map { UInt8($0 & 0xFF) })  // 130 KiB
        let fragmenter = DCGFragmenter(sessionID: "s", maxFragmentBytes: 60 * 1024)
        let fragments = try fragmenter.fragment(
            payload: payload, messageID: 1, startingSequenceNumber: 1, handlerType: "files"
        )
        XCTAssertEqual(fragments.count, 3)  // 60k + 60k + 10k
        XCTAssertEqual(fragments.map(\.fragmentID), [0, 1, 2])
        XCTAssertEqual(fragments.map(\.sequenceNumber), [1, 2, 3])
        XCTAssertTrue(fragments.allSatisfy { $0.fragmentCount == 3 })

        let reassembler = DCGReassembler()
        var completed: DCGReassembler.Completed?
        for frag in fragments {
            if let c = try reassembler.accept(frag) { completed = c }
        }
        XCTAssertEqual(reassembler.pendingCount, 0)
        XCTAssertEqual(completed?.payload, payload)
        XCTAssertEqual(completed?.handlerType, "files")
    }

    func testReassembleOutOfOrder() throws {
        let fragmenter = DCGFragmenter(sessionID: "s", maxFragmentBytes: 4)
        let payload = Data([10, 20, 30, 40, 50, 60, 70])  // -> 2 frags (4 + 3)
        var frags = try fragmenter.fragment(
            payload: payload, messageID: 2, startingSequenceNumber: 1, handlerType: "h"
        )
        frags.reverse()  // deliver out of order
        let reassembler = DCGReassembler()
        var completed: DCGReassembler.Completed?
        for f in frags { if let c = try reassembler.accept(f) { completed = c } }
        XCTAssertEqual(completed?.payload, payload)
    }

    func testDuplicateFragmentRejected() throws {
        let fragmenter = DCGFragmenter(sessionID: "s", maxFragmentBytes: 4)
        let frags = try fragmenter.fragment(
            payload: Data([1, 2, 3, 4, 5]), messageID: 3, startingSequenceNumber: 1, handlerType: "h"
        )
        let reassembler = DCGReassembler()
        _ = try reassembler.accept(frags[0])
        XCTAssertThrowsError(try reassembler.accept(frags[0])) { error in
            XCTAssertEqual(error as? DCGFramingError,
                           .duplicateFragment(messageID: 3, fragmentID: 0))
        }
    }

    func testEmptyPayloadRejected() {
        let fragmenter = DCGFragmenter(sessionID: "s")
        XCTAssertThrowsError(
            try fragmenter.fragment(payload: Data(), messageID: 1,
                                    startingSequenceNumber: 1, handlerType: "h")
        ) { XCTAssertEqual($0 as? DCGFramingError, .emptyPayload) }
    }

    // MARK: Connection routing over a mock channel

    func testConnectionSendFragmentsAndReceive() throws {
        let mock = MockChannel()
        let conn = DCGConnection(channel: mock, sessionID: "sess", maxFragmentBytes: 8)
        conn.autoAck = false

        var received: Data?
        conn.onPayload = { received = $0.payload }
        conn.start()

        // Send a 20-byte payload -> 3 fragments serialized onto the channel.
        let payload = Data((0..<20).map { UInt8($0) })
        try conn.send(payload: payload, handlerType: "clipboard")
        XCTAssertEqual(mock.sent.count, 3)

        // Loop every sent frame back in; connection should reassemble the payload.
        for frame in mock.sent { mock.deliver(frame) }
        XCTAssertEqual(received, payload)
    }

    func testConnectionAutoAck() throws {
        let mock = MockChannel()
        let conn = DCGConnection(channel: mock, sessionID: "sess", maxFragmentBytes: 64)
        conn.autoAck = true
        conn.start()

        // Build one inbound single-fragment frame and deliver it.
        var base = Maclink_Platform_V1_DcgBaseMessage()
        base.sessionID = "sess"; base.type = .fragment; base.version = 1
        var frag = Maclink_Platform_V1_DcgFragmentMessage()
        frag.base = base; frag.messageID = 1; frag.fragmentID = 0
        frag.fragmentCount = 1; frag.sequenceNumber = 99
        frag.handlerType = "h"; frag.raw = Data([9, 9])
        mock.deliver(try frag.serializedData())

        // One ack frame should have been written back.
        XCTAssertEqual(mock.sent.count, 1)
        let ack = try Maclink_Platform_V1_DcgAckMessage(serializedBytes: mock.sent[0])
        XCTAssertEqual(ack.sequenceNumber, 99)
        XCTAssertTrue(ack.success)
    }
}

// MARK: - Mock channel

final class MockChannel: DCGChannel {
    var onReceive: ((Data) -> Void)?
    var onStateChange: ((DCGChannelState) -> Void)?
    private(set) var sent: [Data] = []

    func start() { onStateChange?(.connected) }
    func stop() { onStateChange?(.disconnected(reason: nil)) }
    func send(_ frame: Data, completion: @escaping (Error?) -> Void) {
        sent.append(frame)
        completion(nil)
    }
    func deliver(_ frame: Data) { onReceive?(frame) }
}
