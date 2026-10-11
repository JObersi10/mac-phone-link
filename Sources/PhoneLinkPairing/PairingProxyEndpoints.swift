// PairingProxyEndpoints — the Device Pairing Proxy REST surface.
//
// Clean-room model of the cloud pairing endpoints, from observed path + host
// facts only. The proxy is hosted under the DCG domain; the QR/PIN flow drives
// a PinSession through a fixed sequence of states, and the crypto-trust ceremony
// finishes against a PairingSession.
//
// Auth: the proxy requires an MSA token (a plain DCG access token is rejected),
// and — like the DCG resource — is expected to be first-party gated, so a
// third-party client may be refused. That is a documented interop finding, not
// a defect in this client.
//
// SPDX-License-Identifier: MIT

import Foundation

public enum DCGEnvironment: String, Sendable, CaseIterable {
    case production
    case dogfood
    case beta

    public var host: String {
        switch self {
        case .production: return "dcg.microsoft.com"
        case .dogfood:    return "dcg-df.microsoft.com"
        case .beta:       return "dcg-beta.microsoft.com"
        }
    }

    public var baseURL: URL { URL(string: "https://\(host)")! }
}

/// The states a PinSession (the QR/PIN flow) moves through, in order.
public enum PinSessionState: String, Sendable, CaseIterable {
    case created
    case qrScanned
    case pinTyped
    case validateTrustInfo
    case accountTransferred
}

public struct PairingProxyEndpoints: Sendable {
    public let environment: DCGEnvironment
    private let root = "DevicePairingProxy"

    public init(environment: DCGEnvironment = .production) {
        self.environment = environment
    }

    private func url(_ path: String) -> URL {
        environment.baseURL.appendingPathComponent(root).appendingPathComponent(path)
    }

    // MARK: PinSessions (QR / PIN flow)

    /// `POST /DevicePairingProxy/PinSessions/{id}` — create the session.
    public func createPinSession(id: String) -> URL { url("PinSessions/\(id)") }

    /// `GET  /DevicePairingProxy/PinSessions/{id}/State` — poll current state.
    public func pinSessionState(id: String) -> URL { url("PinSessions/\(id)/State") }

    /// State-transition reports the phone posts as the ceremony advances.
    public func pinSessionQRScanned(id: String) -> URL { url("PinSessions/\(id)/QRScanned") }
    public func pinSessionPINTyped(id: String) -> URL { url("PinSessions/\(id)/PINTyped") }
    public func pinSessionValidateTrustInfo(id: String) -> URL { url("PinSessions/\(id)/ValidateTrustInfo") }
    public func pinSessionAccountTransferred(id: String) -> URL { url("PinSessions/\(id)/AccountTransferred") }

    // MARK: PairingSessions (crypto-trust ceremony)

    /// `POST /DevicePairingProxy/PairingSessions/{id}/Complete`.
    public func pairingSessionComplete(id: String) -> URL { url("PairingSessions/\(id)/Complete") }

    // MARK: PhoneSessions

    public func phoneSessionState(id: String) -> URL { url("PhoneSessions/\(id)/State") }
    public func phoneSessionPhoneState(id: String) -> URL { url("PhoneSessions/\(id)/PhoneState") }
}
