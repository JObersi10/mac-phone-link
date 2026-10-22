// AccountLinkCoordinator — the end-to-end wiring of the account/device path:
//   resolve client id → device-code sign-in → DDS register → open Hub Relay →
//   bridge to the FeatureHub (clipboard / notifications / messages).
//
// This is the "finish the wiring" step. It is runnable: it makes the real calls
// in order. Two seams are UNVERIFIED against live traffic and flagged inline:
//   - `hubURL` is the negotiated Hub Relay endpoint (supplied in config here).
//   - the DDS `register` body + the broker-ticket acquisition for DCG.
// And the usual ceiling applies: DCG only issues to the first-party client id,
// so this completes only when the caller supplies an id DCG accepts. No client
// id is embedded — it comes from `ClientIdResolver` (env/config/explicit).
//
// SPDX-License-Identifier: MIT

import Foundation
import DCGTransport
import DCGAuth

// MARK: - Feature transport over a DCG/Hub Relay channel

/// Bridges a `DCGChannel` (e.g. `SignalRDCGChannel`) to the `FeatureHub` by
/// wrapping/unwrapping `YPPEnvelope`s. Route == feature handler type.
public final class DCGFeatureTransport: FeatureTransport {
    private let channel: DCGChannel
    public var onPayload: ((String, Data) -> Void)?

    public init(channel: DCGChannel) {
        self.channel = channel
        channel.onReceive = { [weak self] data in
            guard let env = try? YPPEnvelope(decodingJSON: data) else { return }
            self?.onPayload?(env.route, env.payload)
        }
    }

    public func send(handlerType: String, _ payload: Data) {
        let env = YPPEnvelope(route: handlerType,
                              contentType: "application/octet-stream",
                              payload: payload)
        guard let data = try? env.encodedJSON() else { return }
        channel.send(data) { _ in }
    }

    public func start() { channel.start() }
    public func stop() { channel.stop() }
}

// MARK: - Coordinator

public struct AccountLinkConfig: Sendable {
    public var deviceDisplayName: String
    /// The negotiated Hub Relay endpoint. UNVERIFIED wire detail — in the real
    /// client this comes from the DCG/DDS negotiate response (`signalRDetails`);
    /// supply it here until that negotiation is implemented.
    public var hubURL: URL
    public var scopes: [String]
    public var capabilities: [String]

    public init(hubURL: URL,
                deviceDisplayName: String = Host.current().localizedName ?? "Mac",
                scopes: [String] = ["openid", "profile", "offline_access"],
                capabilities: [String] = ["clipboard", "notifications"]) {
        self.hubURL = hubURL
        self.deviceDisplayName = deviceDisplayName
        self.scopes = scopes
        self.capabilities = capabilities
    }
}

@MainActor
public final class AccountLinkCoordinator {
    public enum LinkError: Error { case noClientId }

    private let config: AccountLinkConfig
    public private(set) var hub: FeatureHub?

    public init(config: AccountLinkConfig) { self.config = config }

    /// Run the full account/device link. `present` is called with the
    /// device-code challenge so the UI can show the user code + verification URL.
    /// Returns the wired `FeatureHub` once the relay channel is started.
    @discardableResult
    public func link(
        present: @escaping @Sendable (DeviceCodeChallenge) -> Void,
        handlers: [FeatureHandler] = []
    ) async throws -> FeatureHub {
        // 1. Client id — caller-supplied; nothing embedded.
        guard let clientId = ClientIdResolver.resolve() else { throw LinkError.noClientId }

        // 2. Device-code sign-in → MSA token.
        let auth = DeviceCodeAuth(config: DeviceCodeConfig(clientId: clientId, scopes: config.scopes))
        let token = try await auth.authenticate(present: present)
        let accessToken = token.accessToken

        // 3. Register into the DDS device graph (best-effort; body UNVERIFIED,
        //    and the endpoint may be gated — non-fatal so bring-up can proceed).
        let dds = DDSDeviceRegistration(authHeader: { ("Authorization", "Bearer \(accessToken)") })
        let registration = DeviceRegistration(
            selfClientId: clientId,
            displayName: config.deviceDisplayName,
            publicCertificate: "",            // self-signed cert goes here once EnrollDevice lands
            trustType: "AccountPairingD2D",
            capabilities: config.capabilities)
        _ = try? await dds.register(registration)

        // 4. Open the Hub Relay channel and bridge it to a FeatureHub.
        let channel = SignalRDCGChannel(config: DCGHubConfig(
            url: config.hubURL,
            accessTokenProvider: { accessToken }))
        let transport = DCGFeatureTransport(channel: channel)
        let hub = FeatureHub(transport: transport)

        // 5. Attach feature handlers, start the channel.
        for handler in handlers { hub.register(handler) }
        transport.start()
        self.hub = hub
        return hub
    }
}
