import Foundation
import CryptoKit

/// Symmetric encryption for the companion channel.
///
/// Design modeled on the AirSync backend (an open AirSync-style link): a single
/// AES-256-GCM key is shared out-of-band via the pairing QR code, and every
/// JSON frame on the wire is sealed with it. This is our own implementation
/// (standard `CryptoKit`); no third-party source is used — see NOTICE.md.
///
/// Wire form of a sealed frame: `base64( nonce || ciphertext || tag )`, exactly
/// what `AES.GCM.SealedBox.combined` produces, so the Android side can decrypt
/// with the platform `javax.crypto` GCM primitives without any custom framing.
public struct CompanionCrypto {
    public let key: SymmetricKey

    public init(key: SymmetricKey) { self.key = key }

    /// Build from the base64 key string carried in the pairing code.
    public init?(base64Key: String) {
        guard let data = Data(base64Encoded: base64Key), data.count == 32 else { return nil }
        self.key = SymmetricKey(data: data)
    }

    /// Generate a fresh random 256-bit key.
    public static func generateKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    /// The key as the base64 string embedded in the pairing QR code.
    public var base64Key: String { key.withUnsafeBytes { Data($0).base64EncodedString() } }

    /// Seal plaintext → `nonce || ciphertext || tag`.
    public func seal(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CompanionCryptoError.sealFailed }
        return combined
    }

    /// Open `nonce || ciphertext || tag` → plaintext.
    public func open(_ combined: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    /// Encrypt a frame to the on-wire base64 string (no trailing newline).
    public func sealToBase64(_ plaintext: Data) throws -> String {
        try seal(plaintext).base64EncodedString()
    }

    /// Decrypt one on-wire base64 frame back to plaintext.
    public func openFromBase64(_ base64: String) throws -> Data {
        guard let combined = Data(base64Encoded: base64) else { throw CompanionCryptoError.badBase64 }
        return try open(combined)
    }
}

public enum CompanionCryptoError: Error, Equatable {
    case sealFailed
    case badBase64
}
