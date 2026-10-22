// YPPEnvelope — the YPP feature-message wrapper that rides a DCG/Hub Relay
// channel. Step 3 glue between the transport (SignalRDCGChannel) and the
// per-feature handlers (clipboard, notifications, messages…).
//
// Envelope fields are those we documented from the YPP managed stack
// (docs/FINDINGS.md): `_requestId`, `_route`, `contentType`, `remoteAppId`,
// and a `gzip` flag on the payload. The payload itself is opaque bytes (a
// feature proto / JSON). The exact gzip framing and content-type vocabulary
// are partially UNVERIFIED — modeled faithfully from the field names, confirm
// against a live capture.
//
// SPDX-License-Identifier: MIT

import Foundation

public struct YPPEnvelope: Sendable, Equatable {
    /// `_requestId` — correlates a request with its response (GUID string).
    public var requestId: String
    /// `_route` — the feature route / verb (e.g. a feature path or opcode name).
    public var route: String
    /// `contentType` — payload media/schema type.
    public var contentType: String
    /// `remoteAppId` — the target app/feature id on the peer.
    public var remoteAppId: String?
    /// Whether `payload` is gzip-compressed.
    public var gzip: Bool
    /// Opaque feature payload (decompressed form in memory).
    public var payload: Data

    public init(route: String,
                contentType: String,
                payload: Data,
                remoteAppId: String? = nil,
                requestId: String = UUID().uuidString,
                gzip: Bool = false) {
        self.requestId = requestId
        self.route = route
        self.contentType = contentType
        self.remoteAppId = remoteAppId
        self.gzip = gzip
        self.payload = payload
    }
}

// MARK: - JSON wire form

extension YPPEnvelope {
    /// The on-the-wire JSON shape (payload base64-encoded). The `gzip` flag
    /// reflects whether the *encoded* payload bytes are compressed; this codec
    /// carries the flag through but does not itself (de)compress — a caller
    /// supplies already-(de)compressed `payload` bytes. Keeps the compression
    /// dependency out of the model until the framing is confirmed on the wire.
    struct Wire: Codable {
        let _requestId: String
        let _route: String
        let contentType: String
        let remoteAppId: String?
        let gzip: Bool
        let payload: String   // base64
    }

    public func encodedJSON() throws -> Data {
        let wire = Wire(_requestId: requestId, _route: route, contentType: contentType,
                        remoteAppId: remoteAppId, gzip: gzip,
                        payload: payload.base64EncodedString())
        return try JSONEncoder().encode(wire)
    }

    public init(decodingJSON data: Data) throws {
        let w = try JSONDecoder().decode(Wire.self, from: data)
        guard let payload = Data(base64Encoded: w.payload) else {
            throw YPPEnvelopeError.malformedPayload
        }
        self.init(route: w._route, contentType: w.contentType, payload: payload,
                  remoteAppId: w.remoteAppId, requestId: w._requestId, gzip: w.gzip)
    }
}

public enum YPPEnvelopeError: Error, Equatable {
    case malformedPayload
}
