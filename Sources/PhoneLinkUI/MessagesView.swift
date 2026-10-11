// MessagesView — compose and send an SMS/RCS message through MessagingClient.
// Minimal compose UI; a full thread list arrives once a live channel feeds
// inbound messages.
//
// SPDX-License-Identifier: MIT

#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI

public struct MessagesView: View {
    @ObservedObject private var client: MessagingClient
    @State private var recipients = ""
    @State private var messageText = ""

    public init(client: MessagingClient) {
        self.client = client
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New message").font(.headline)
            TextField("Recipients (comma-separated numbers)", text: $recipients)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $messageText)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                statusView
                Spacer()
                Button("Send") {
                    client.sendMessage(to: recipients.split(separator: ",").map(String.init), body: messageText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(recipients.isEmpty || messageText.isEmpty)
            }
            Spacer()
        }
        .padding(16)
    }

    @ViewBuilder private var statusView: some View {
        switch client.sendState {
        case .idle: EmptyView()
        case .sending: Label("Queued (needs a connected phone)", systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
        case .sent(let id): Label("Sent (\(id))", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let m): Label(m, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red)
        }
    }
}
#endif
