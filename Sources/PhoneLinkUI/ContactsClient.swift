// ContactsClient — search the phone's contacts from the Mac.
//
// A FeatureHandler over the "contacts" channel: encodes a ContactSearchRequest
// and decodes ContactSearchResponse into observable results. Transport-agnostic.
//
// SPDX-License-Identifier: MIT

import Foundation
import Combine
import PhoneLinkProtos

/// A display-shaped contact.
public struct ContactRow: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let numbers: [String]
    init(_ c: Maclink_Contacts_V1_ContactItem) {
        self.id = c.id.isEmpty ? UUID().uuidString : c.id
        self.name = c.displayName.isEmpty
            ? [c.firstName, c.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            : c.displayName
        self.numbers = c.phoneNumbers.map { $0.displayValue.isEmpty ? $0.value : $0.displayValue }
    }
}

@MainActor
public final class ContactsClient: ObservableObject, FeatureHandler {
    public let handlerType = "contacts"

    @Published public private(set) var results: [ContactRow] = []
    @Published public private(set) var isSearching = false

    private var send: ((Data) -> Void)?

    public init() {}

    public func bindSend(_ send: @escaping (Data) -> Void) { self.send = send }

    public func search(_ query: String, maxResults: Int32 = 50, allowFuzzy: Bool = true) {
        guard let send else { return }
        var req = Maclink_Contacts_V1_ContactSearchRequestMessage()
        req.query = query
        req.maxResults = maxResults
        req.allowFuzzy = allowFuzzy
        guard let data = try? req.serializedData() else { return }
        isSearching = true
        send(data)
    }

    public func handleIncoming(_ payload: Data) {
        isSearching = false
        guard let resp = try? Maclink_Contacts_V1_ContactSearchResponseMessage(serializedBytes: payload) else { return }
        results = resp.contacts.map(ContactRow.init)
    }
}
