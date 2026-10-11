// DCGSession — the unified manager that wires the two authentication layers to
// the transport:
//   1. MSA/Entra access token (DCGAuth) -> SignalR hub bearer auth.
//   2. Device-trust JWT (DeviceTrustAuthorizer + DRS nonce) -> per-message
//      SideChannelAuthorization.
//
// It owns the DCGConnection and exposes a single place to start the session and
// mint fresh authorizations. The MSA token is supplied via an async provider
// (so the caller controls MSAL interactive/silent + UI), and the SignalR
// channel is injectable for testing.
//
// SPDX-License-Identifier: MIT

import Foundation
import PhoneLinkProtos
import DCGAuth

public struct DCGSessionConfig {
    public var hubURL: URL
    /// Tenant / home authority used for DRS nonce discovery.
    public var tenant: String
    public var sessionID: String
    public var maxFragmentBytes: Int

    public init(hubURL: URL, tenant: String, sessionID: String = UUID().uuidString,
                maxFragmentBytes: Int = DCGFraming.defaultMaxFragmentBytes) {
        self.hubURL = hubURL
        self.tenant = tenant
        self.sessionID = sessionID
        self.maxFragmentBytes = maxFragmentBytes
    }
}

public final class DCGSession {
    public typealias AccessTokenProvider = () async throws -> String
    public typealias ChannelFactory = (DCGHubConfig) -> DCGChannel

    private let config: DCGSessionConfig
    private let accessTokenProvider: AccessTokenProvider
    private let deviceTrust: DeviceTrustAuthorizer
    private let nonceClient: DRSNonceClient
    private let discovery: DRSDiscoveryClient
    private let channelFactory: ChannelFactory

    private var cachedAccessToken: String?
    public private(set) var connection: DCGConnection?

    /// - Parameters:
    ///   - accessTokenProvider: returns a current MSA/Entra DCG access token
    ///     (wrap DCGAuthenticator here).
    ///   - deviceTrust: mints the device-trust JWT authorization.
    ///   - channelFactory: builds the byte channel; defaults to SignalR. Inject
    ///     a mock in tests.
    public init(
        config: DCGSessionConfig,
        accessTokenProvider: @escaping AccessTokenProvider,
        deviceTrust: DeviceTrustAuthorizer,
        nonceClient: DRSNonceClient = DRSNonceClient(),
        discovery: DRSDiscoveryClient = DRSDiscoveryClient(),
        channelFactory: ChannelFactory? = nil
    ) {
        self.config = config
        self.accessTokenProvider = accessTokenProvider
        self.deviceTrust = deviceTrust
        self.nonceClient = nonceClient
        self.discovery = discovery
        self.channelFactory = channelFactory ?? { hubConfig in SignalRDCGChannel(config: hubConfig) }
    }

    /// Acquire the MSA token, build the channel + connection, and start it.
    @discardableResult
    public func start() async throws -> DCGConnection {
        let token = try await accessTokenProvider()
        cachedAccessToken = token

        let hubConfig = DCGHubConfig(
            url: config.hubURL,
            accessTokenProvider: { [weak self] in self?.cachedAccessToken }
        )
        let channel = channelFactory(hubConfig)
        let connection = DCGConnection(
            channel: channel,
            sessionID: config.sessionID,
            maxFragmentBytes: config.maxFragmentBytes
        )
        self.connection = connection
        connection.start()
        return connection
    }

    /// Refresh the cached MSA access token used by the hub bearer provider.
    public func refreshAccessToken() async throws {
        cachedAccessToken = try await accessTokenProvider()
    }

    /// Mint a fresh device-trust authorization bound to a newly discovered DRS
    /// nonce — the full auth→transport join for an outgoing side-channel request.
    public func currentAuthorization() async throws -> Maclink_Sidechannel_V1_Authorization {
        let nonce = try await nonceClient.requestNonce(
            discoveringFor: config.tenant, discovery: discovery
        )
        return try deviceTrust.makeAuthorization(nonce: nonce)
    }
}
