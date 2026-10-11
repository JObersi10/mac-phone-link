// ClipboardSync — mirrors the Mac pasteboard to/from the phone over a channel.
//
// Outbound: poll NSPasteboard.changeCount; when the local clipboard changes,
// serialize it as a clipboard ResponseMessage and hand it to `sink`.
// Inbound: parse a ResponseMessage from the phone and write its items to the
// local pasteboard. The proto <-> value mapping is split out as pure functions
// so it's testable without a pasteboard.
//
// SPDX-License-Identifier: MIT

import Foundation
import PhoneLinkProtos
#if canImport(AppKit)
import AppKit
#endif

public enum ClipboardCodec {
    /// Build a content item carrying text.
    public static func textItem(_ text: String) -> Maclink_Clipboard_V1_Item {
        var item = Maclink_Clipboard_V1_Item()
        item.itemType = .textPlain
        item.text = text
        item.createdTime = .init(date: Date())
        return item
    }

    /// Build a content item carrying image bytes (e.g. PNG).
    public static func imageItem(_ bytes: Data) -> Maclink_Clipboard_V1_Item {
        var item = Maclink_Clipboard_V1_Item()
        item.itemType = .image
        item.imageBytes = bytes
        item.createdTime = .init(date: Date())
        return item
    }

    /// Wrap items in an OK response message.
    public static func response(_ items: [Maclink_Clipboard_V1_Item],
                                correlationID: String = "") -> Maclink_Clipboard_V1_ResponseMessage {
        var msg = Maclink_Clipboard_V1_ResponseMessage()
        msg.clipboardItem = items
        msg.status = .ok
        msg.correlationID = correlationID
        return msg
    }

    /// Extract the first text payload from a response, if any.
    public static func firstText(in response: Maclink_Clipboard_V1_ResponseMessage) -> String? {
        response.clipboardItem.first { $0.itemType == .textPlain && $0.hasText && !$0.text.isEmpty }?.text
    }
}

#if canImport(AppKit)
@MainActor
public final class ClipboardSync: FeatureHandler {
    public let handlerType = "clipboard"
    /// FeatureHub injects the outbound sender here (same as setting `sink`).
    public func bindSend(_ send: @escaping (Data) -> Void) { self.sink = send }

    /// Called with a serialized ResponseMessage when the local clipboard changes.
    public var sink: ((Data) -> Void)?

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    /// Guard so applying a remote item doesn't immediately echo back out.
    private var suppressNextChange = false

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Begin polling the local pasteboard for changes.
    public func start(pollInterval: TimeInterval = 0.75) {
        stop()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkLocalChange() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkLocalChange() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if suppressNextChange { suppressNextChange = false; return }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        let msg = ClipboardCodec.response([ClipboardCodec.textItem(text)])
        if let data = try? msg.serializedData() { sink?(data) }
    }

    /// Apply an incoming serialized ResponseMessage to the local pasteboard.
    public func handleIncoming(_ data: Data) {
        guard let msg = try? Maclink_Clipboard_V1_ResponseMessage(serializedBytes: data) else { return }
        guard let text = ClipboardCodec.firstText(in: msg) else { return }
        suppressNextChange = true
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }
}
#endif
