// SideChannelAuth — bridges the device-trust signing layer (DCGAuth) to the
// message transport. Produces `SideChannelAuthorization` protobufs from a
// signed device-trust JWT and stamps outgoing side-channel requests with them.
//
// SPDX-License-Identifier: MIT

import Foundation
import PhoneLinkProtos
import DCGAuth

/// Holds the device-trust signer + identity and mints authorization objects.
/// This is the join point between authentication and the encrypted transport:
/// the server issues a nonce, this authorizer signs it, and the resulting JWT
/// travels in each side-channel request/response.
public final class DeviceTrustAuthorizer {
    private let signer: JWTSigner
    private let dcgClientId: String
    private let issuer: String?
    private let audience: String?
    private let lifetime: TimeInterval

    public init(
        signer: JWTSigner,
        dcgClientId: String,
        issuer: String? = nil,
        audience: String? = nil,
        lifetime: TimeInterval = 300
    ) {
        self.signer = signer
        self.dcgClientId = dcgClientId
        self.issuer = issuer
        self.audience = audience
        self.lifetime = lifetime
    }

    /// Sign a fresh JWT (optionally binding a server-issued nonce) and wrap it
    /// as a `SideChannelAuthorization`.
    public func makeAuthorization(nonce: String? = nil) throws -> Maclink_Sidechannel_V1_Authorization {
        let claims = DeviceTrustClaims(
            dcgClientId: dcgClientId,
            nonce: nonce,
            issuer: issuer,
            audience: audience,
            lifetime: lifetime
        )
        let jwt = try DeviceTrustJWT.sign(claims: claims, with: signer)
        return SideChannelAuth.authorization(jwt: jwt)
    }

    /// Return a signed client request with the authorization attached.
    public func authorize(
        _ request: inout Maclink_Sidechannel_V1_ClientRequest,
        nonce: String? = nil
    ) throws {
        request.authorization = try makeAuthorization(nonce: nonce)
    }
}

public enum SideChannelAuth {
    /// Wrap an already-signed compact JWT as a `SideChannelAuthorization`.
    public static func authorization(jwt: String) -> Maclink_Sidechannel_V1_Authorization {
        var auth = Maclink_Sidechannel_V1_Authorization()
        auth.signedJwtPayload = jwt
        return auth
    }
}

// MARK: - Transport bridge

extension DCGConnection {
    /// Install a device-trust authorizer so the connection can emit a signed
    /// authorization on demand (e.g. to stamp platform/side-channel frames).
    ///
    /// The DCG fragment framing itself does not carry the JWT field, so this
    /// returns the authorization for callers that build side-channel
    /// request/response messages over this connection.
    public func authorization(
        using authorizer: DeviceTrustAuthorizer,
        nonce: String? = nil
    ) throws -> Maclink_Sidechannel_V1_Authorization {
        try authorizer.makeAuthorization(nonce: nonce)
    }
}
