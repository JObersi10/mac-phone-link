// Tests for the UI connection view model: payload decoding, state mapping,
// and transport binding (over a mock channel).
//
// SPDX-License-Identifier: MIT

import XCTest
import Foundation
@testable import PhoneLinkProtos
@testable import DCGTransport
@testable import PhoneLinkUI

@MainActor
final class ConnectionViewModelTests: XCTestCase {

    private func notificationPayload(_ infos: [(key: String, title: String, text: String, app: String)]) throws -> Data {
        var resp = Maclink_Notification_V1_ResponseMessage()
        resp.status = .ok
        resp.notifications = infos.map {
            var n = Maclink_Notification_V1_NotificationInfo()
            n.key = $0.key; n.title = $0.title; n.text = $0.text; n.appName = $0.app
            n.postTime = 1_700_000_000_000
            return n
        }
        return try resp.serializedData()
    }

    func testDecodeNotifications() throws {
        let data = try notificationPayload([
            ("k1", "Hello", "World", "Messages"),
            ("k2", "Ping", "", "Signal"),
        ])
        let items = ConnectionViewModel.decodeNotifications(from: data)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Hello")
        XCTAssertEqual(items[0].appName, "Messages")
    }

    func testDecodeGarbageReturnsEmpty() {
        XCTAssertTrue(ConnectionViewModel.decodeNotifications(from: Data([0xDE, 0xAD])).isEmpty
                      || ConnectionViewModel.decodeNotifications(from: Data([0xDE, 0xAD])).count == 0)
    }

    func testMergeDeduplicatesAndNewestFirst() {
        let vm = ConnectionViewModel()
        vm.merge([NotificationItem(id: "a", title: "A", text: "", appName: "x", postTime: .init())])
        vm.merge([
            NotificationItem(id: "a", title: "A-dup", text: "", appName: "x", postTime: .init()),
            NotificationItem(id: "b", title: "B", text: "", appName: "x", postTime: .init()),
        ])
        XCTAssertEqual(vm.notifications.count, 2)
        XCTAssertEqual(vm.notifications.first?.id, "b")  // newest inserted at front
    }

    func testStateLabels() {
        XCTAssertEqual(UIConnectionState.connected.label, "Connected")
        XCTAssertTrue(UIConnectionState.connected.isConnected)
        XCTAssertEqual(UIConnectionState.disconnected(reason: "bye").label, "Disconnected: bye")
        XCTAssertFalse(UIConnectionState.idle.isConnected)
    }

    func testBindReceivesNotificationsFromConnection() throws {
        let mock = MockChannel()
        let conn = DCGConnection(channel: mock, sessionID: "s", maxFragmentBytes: 1024)
        conn.autoAck = false
        let vm = ConnectionViewModel()
        vm.bind(to: conn)
        conn.start()

        // Feed a single-fragment notification frame tagged with the handler type.
        let payload = try notificationPayload([("k9", "Mirror", "Body", "App")])
        var base = Maclink_Platform_V1_DcgBaseMessage()
        base.sessionID = "s"; base.type = .fragment; base.version = 1
        var frag = Maclink_Platform_V1_DcgFragmentMessage()
        frag.base = base; frag.messageID = 1; frag.fragmentID = 0; frag.fragmentCount = 1
        frag.sequenceNumber = 1; frag.handlerType = "notification"; frag.raw = payload
        mock.deliver(try frag.serializedData())

        // onPayload hops through a Task { @MainActor }; drain the main queue.
        let exp = expectation(description: "notification surfaced")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(vm.notifications.count, 1)
        XCTAssertEqual(vm.notifications.first?.title, "Mirror")
    }
}
