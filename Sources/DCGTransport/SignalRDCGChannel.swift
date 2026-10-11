// SignalRDCGChannel — a DCGChannel backed by a SignalR hub connection, the
// transport Phone Link uses to reach the Device Connectivity Gateway.
//
// The DCG hub method names are not published; they are configurable here
// (`HubMethods`) with sensible placeholders. Supply a bearer-token provider
// (e.g. backed by DCGAuth) so the hub negotiation carries MSA/Entra auth.
//
// SPDX-License-Identifier: MIT

import Foundation
import SignalRClient

public struct DCGHubConfig {
    /// DCG hub URL (negotiate endpoint).
    public var url: URL
    /// Returns a current bearer access token for the hub (from DCGAuth).
    public var accessTokenProvider: () -> String?
    /// Hub method the server invokes to push frames to this client.
    public var receiveMethod: String
    /// Hub method this client invokes to send frames to the server.
    public var sendMethod: String

    public init(
        url: URL,
        accessTokenProvider: @escaping () -> String?,
        receiveMethod: String = "ReceiveMessage",
        sendMethod: String = "SendMessage"
    ) {
        self.url = url
        self.accessTokenProvider = accessTokenProvider
        self.receiveMethod = receiveMethod
        self.sendMethod = sendMethod
    }
}

public final class SignalRDCGChannel: DCGChannel, HubConnectionDelegate {
    public var onReceive: ((Data) -> Void)?
    public var onStateChange: ((DCGChannelState) -> Void)?

    private let config: DCGHubConfig
    private let connection: HubConnection

    public init(config: DCGHubConfig) {
        self.config = config
        self.connection = HubConnectionBuilder(url: config.url)
            .withHttpConnectionOptions { options in
                options.accessTokenProvider = { config.accessTokenProvider() }
            }
            .build()
        self.connection.delegate = self

        // Server -> client frames arrive as a byte array argument.
        self.connection.on(method: config.receiveMethod) { [weak self] (argumentExtractor: ArgumentExtractor) in
            guard let self else { return }
            if let bytes = try? argumentExtractor.getArgument(type: [UInt8].self) {
                self.onReceive?(Data(bytes))
            }
        }
    }

    public func start() {
        onStateChange?(.connecting)
        connection.start()
    }

    public func stop() {
        connection.stop()
    }

    public func send(_ frame: Data, completion: @escaping (Error?) -> Void) {
        connection.send(method: config.sendMethod, [UInt8](frame)) { error in
            completion(error)
        }
    }

    // MARK: HubConnectionDelegate

    public func connectionDidOpen(hubConnection: HubConnection) {
        onStateChange?(.connected)
    }

    public func connectionDidFailToOpen(error: Error) {
        onStateChange?(.disconnected(reason: String(describing: error)))
    }

    public func connectionDidClose(error: Error?) {
        onStateChange?(.disconnected(reason: error.map { String(describing: $0) }))
    }
}
