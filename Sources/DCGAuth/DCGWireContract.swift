// DCGWireContract — the confirmed on-the-wire contract for DCG authentication,
// recovered by static analysis of the shipped Windows client's auth assembly
// (`YourPhone.YPP.Auth`). See docs/FINDINGS.md § "DCG auth + device identity".
//
// These are protocol facts (hostnames, header names, api-version, algorithm
// identifiers, enum names), not vendor source. They correct the earlier
// assumption in DCGAuth.swift / DRSNonce.swift that DCG used an Entra
// `DCG.ReadWrite` scope and a Workplace-Join (DRS) nonce. The shipped client
// instead rides a Microsoft Account (MSA) broker ticket and a DCG-native nonce.
//
// SPDX-License-Identifier: MIT

import Foundation

/// The DCG authentication wire contract as observed in the shipped client.
///
/// Nothing here is executed by us; it documents what the real client sends so a
/// clean-room implementation can match it. The sequence is still to be confirmed
/// against live traffic (docs/EVIDENCE_PLAN.md item A/C).
public enum DCGWireContract {

    // MARK: Hosts

    /// The DCG MSA-token / nonce / identity host the client authenticates against.
    public static let authHost = URL(string: "https://msatoken.dcg.microsoft.com")!

    /// MSA consumers authority the account ticket is acquired from.
    public static let msaAuthority = URL(string: "https://login.microsoft.com/consumers")!

    // MARK: Request parameters

    /// The api-version the client pins on auth requests.
    public static let apiVersion = "2.0"

    /// Query parameter names on the token/nonce request (`…&api-version=2.0&clientid=<id>`).
    public static let apiVersionParam = "api-version"
    public static let clientIdParam = "clientid"

    // MARK: Headers

    /// Standard bearer header; value is `"Bearer " + <msaToken>`.
    public static let authorizationHeader = "Authorization"
    public static let bearerPrefix = "Bearer "

    /// The header that tells DCG the bearer is a Microsoft Account ticket.
    /// This is the key difference from an ordinary Entra OAuth call.
    public static let authorizationTypeHeader = "Authorization-Type"
    public static let authorizationTypeMSA = "MSA"

    // MARK: MSA scope strategy

    /// The client requests a SAPI MSA token first, then falls back to an
    /// `MBI_SSL`-form device-broker scope (see README / FINDINGS). We do not
    /// hardcode the exact scope literal here because it is environment- and
    /// broker-dependent; `mbiSslFallbackMarker` records the observed fallback.
    public static let mbiSslFallbackMarker = "MBI_SSL"

    // MARK: Crypto algorithms

    /// JWT signing algorithm: ECDSA on P-384 with SHA-384.
    public static let jwtSigningAlgorithmURI =
        "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384"

    /// JWE: RSA-OAEP key wrap + AES-256-CBC-HMAC-SHA-512 content encryption.
    public static let jweKeyWrapAlgorithm = "RSA-OAEP"
    public static let jweContentEncryption = "A256CBC-HS512"

    // MARK: Environments

    /// DCG client-id config keys, selected per environment by discovery.
    public enum ClientIdConfigKey {
        public static let `default` = "dcg_client_id"
        public static let prod = "dcg_prod_client_id"
        public static let beta = "dcg_beta_client_id"
        public static let df = "dcg_df_client_id"
    }

    /// Device-to-device trust relationship kinds populated by a completed pair.
    /// `a2d` / `accountPairingD2D` correspond to the QR/account-transfer path.
    public enum TrustType: String, CaseIterable, Sendable {
        case unknown = "Unknown"
        case legacyD2D = "LegacyD2D"
        case accountPairingD2D = "AccountPairingD2D"
        case asyncD2D = "AsyncD2D"
        case a2d = "A2D"
    }
}
