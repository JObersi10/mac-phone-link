// FeaturesViewModel — owns the FeatureHub and the feature clients (messaging,
// contacts, clipboard) and registers them. Defaults to a loopback transport so
// the UI is self-contained until a real channel (Nano/QUIC or DCG) is attached
// via `attach(_:)`.
//
// SPDX-License-Identifier: MIT

import Foundation
import Combine

@MainActor
public final class FeaturesViewModel: ObservableObject {
    public private(set) var hub: FeatureHub
    public let messaging = MessagingClient()
    public let contacts = ContactsClient()
    #if canImport(AppKit)
    public let clipboard = ClipboardSync()
    #endif

    public init(transport: FeatureTransport = LoopbackFeatureTransport()) {
        self.hub = FeatureHub(transport: transport)
        registerAll()
    }

    /// Swap in a real transport (e.g. once connected) and re-register handlers.
    public func attach(_ transport: FeatureTransport) {
        hub = FeatureHub(transport: transport)
        registerAll()
        #if canImport(AppKit)
        clipboard.start()
        #endif
    }

    private func registerAll() {
        hub.register(messaging)
        hub.register(contacts)
        #if canImport(AppKit)
        hub.register(clipboard)
        #endif
    }
}
