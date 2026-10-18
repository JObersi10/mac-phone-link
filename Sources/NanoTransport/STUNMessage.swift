// STUNMessage — a clean-room STUN codec (RFC 5389 / RFC 8489), the base layer of
// the Nano ICE/STUN/TURN transport confirmed by RE of LibNanoAPI (see
// docs/FINDINGS.md § "Nano transport"). Encodes/decodes STUN messages including
// XOR-MAPPED-ADDRESS, FINGERPRINT (CRC-32), and MESSAGE-INTEGRITY (HMAC-SHA1).
//
// This is standard STUN, implemented from the RFCs — no vendor bytes. The
// Nano-proprietary attributes / pseudo-TLS wrapper that ride on top are modeled
// separately once the captured traffic pins their layout.
//
// SPDX-License-Identifier: MIT

import Foundation
import CryptoKit

/// A transport address (IPv4/IPv6 + port) used by STUN address attributes.
public struct STUNAddress: Equatable, Sendable {
    public var ip: String
    public var port: UInt16
    public var isIPv6: Bool
    public init(ip: String, port: UInt16, isIPv6: Bool) {
        self.ip = ip; self.port = port; self.isIPv6 = isIPv6
    }
}

public struct STUNMessage: Equatable {

    /// STUN message class (the 2 class bits of the message-type field).
    public enum MessageClass: UInt16, Sendable {
        case request = 0
        case indication = 1
        case successResponse = 2
        case errorResponse = 3
    }

    // Methods
    public static let methodBinding: UInt16 = 0x0001
    // TURN methods (RFC 8656) we will need later.
    public static let methodAllocate: UInt16 = 0x0003
    public static let methodRefresh: UInt16 = 0x0004
    public static let methodCreatePermission: UInt16 = 0x0008
    public static let methodChannelBind: UInt16 = 0x0009

    public static let magicCookie: UInt32 = 0x2112_A442

    // Common attribute types
    public static let attrMappedAddress: UInt16 = 0x0001
    public static let attrUsername: UInt16 = 0x0006
    public static let attrMessageIntegrity: UInt16 = 0x0008
    public static let attrErrorCode: UInt16 = 0x0009
    public static let attrXorMappedAddress: UInt16 = 0x0020
    public static let attrRealm: UInt16 = 0x0014
    public static let attrNonce: UInt16 = 0x0015
    public static let attrPriority: UInt16 = 0x0024          // ICE (RFC 8445)
    public static let attrUseCandidate: UInt16 = 0x0025      // ICE
    public static let attrFingerprint: UInt16 = 0x8028
    public static let attrIceControlled: UInt16 = 0x8029     // ICE
    public static let attrIceControlling: UInt16 = 0x802A    // ICE

    public var messageClass: MessageClass
    public var method: UInt16
    public var transactionID: Data          // 12 bytes
    public var attributes: [(type: UInt16, value: Data)]

    public init(messageClass: MessageClass,
                method: UInt16 = STUNMessage.methodBinding,
                transactionID: Data = STUNMessage.newTransactionID(),
                attributes: [(type: UInt16, value: Data)] = []) {
        self.messageClass = messageClass
        self.method = method
        self.transactionID = transactionID
        self.attributes = attributes
    }

    public static func == (lhs: STUNMessage, rhs: STUNMessage) -> Bool {
        lhs.messageClass == rhs.messageClass && lhs.method == rhs.method &&
        lhs.transactionID == rhs.transactionID &&
        lhs.attributes.count == rhs.attributes.count &&
        zip(lhs.attributes, rhs.attributes).allSatisfy { $0.type == $1.type && $0.value == $1.value }
    }

    public static func newTransactionID() -> Data {
        var d = Data(count: 12)
        for i in 0..<12 { d[i] = UInt8.random(in: 0...255) }
        return d
    }

    // MARK: Message-type packing (RFC 5389 §6)

    static func packType(method: UInt16, cls: MessageClass) -> UInt16 {
        let m = method
        let c = cls.rawValue
        return ((m & 0x0F80) << 2) | ((m & 0x0070) << 1) | (m & 0x000F)
             | ((c & 0x2) << 7) | ((c & 0x1) << 4)
    }

    static func unpackType(_ t: UInt16) -> (method: UInt16, cls: MessageClass) {
        let method = ((t & 0x3E00) >> 2) | ((t & 0x00E0) >> 1) | (t & 0x000F)
        let cls = ((t & 0x0100) >> 7) | ((t & 0x0010) >> 4)
        return (method, MessageClass(rawValue: cls) ?? .request)
    }

    // MARK: Encode

    /// Serialize without FINGERPRINT/MESSAGE-INTEGRITY unless already present in
    /// `attributes`. Use `encodedWithFingerprint()` / `addMessageIntegrity` for
    /// the integrity attributes, which must be appended with correct length math.
    public func encoded() -> Data {
        var body = Data()
        for attr in attributes { Self.appendAttribute(&body, type: attr.type, value: attr.value) }
        return Self.header(method: method, cls: messageClass, length: body.count, txid: transactionID) + body
    }

    private static func header(method: UInt16, cls: MessageClass, length: Int, txid: Data) -> Data {
        var h = Data()
        h.appendBE(packType(method: method, cls: cls))
        h.appendBE(UInt16(length))
        h.appendBE(magicCookie)
        h.append(txid)
        return h
    }

    static func appendAttribute(_ buf: inout Data, type: UInt16, value: Data) {
        buf.appendBE(type)
        buf.appendBE(UInt16(value.count))
        buf.append(value)
        let pad = (4 - (value.count % 4)) % 4
        if pad > 0 { buf.append(Data(repeating: 0, count: pad)) }
    }

    // MARK: XOR-MAPPED-ADDRESS

    public func xorMappedAddress() -> STUNAddress? {
        guard let v = attributes.first(where: { $0.type == Self.attrXorMappedAddress })?.value else { return nil }
        return Self.decodeXorMappedAddress(v, transactionID: transactionID)
    }

    public mutating func addXorMappedAddress(_ addr: STUNAddress) {
        attributes.append((Self.attrXorMappedAddress,
                           Self.encodeXorMappedAddress(addr, transactionID: transactionID)))
    }

    static func encodeXorMappedAddress(_ addr: STUNAddress, transactionID: Data) -> Data {
        var v = Data([0x00, addr.isIPv6 ? 0x02 : 0x01])
        let xport = addr.port ^ UInt16(magicCookie >> 16)
        v.appendBE(xport)
        let cookieBytes = Data([0x21, 0x12, 0xA4, 0x42])
        if addr.isIPv6 {
            let mask = cookieBytes + transactionID   // 16 bytes
            let raw = ipv6Bytes(addr.ip) ?? Data(count: 16)
            v.append(Data(zip(raw, mask).map { $0 ^ $1 }))
        } else {
            let raw = ipv4Bytes(addr.ip) ?? Data(count: 4)
            v.append(Data(zip(raw, cookieBytes).map { $0 ^ $1 }))
        }
        return v
    }

    static func decodeXorMappedAddress(_ v: Data, transactionID: Data) -> STUNAddress? {
        let b = [UInt8](v)
        guard b.count >= 8 else { return nil }
        let isV6 = b[1] == 0x02
        let xport = (UInt16(b[2]) << 8 | UInt16(b[3]))
        let port = xport ^ UInt16(magicCookie >> 16)
        let cookieBytes: [UInt8] = [0x21, 0x12, 0xA4, 0x42]
        if isV6 {
            guard b.count >= 24 else { return nil }
            let mask = cookieBytes + [UInt8](transactionID)
            let raw = (0..<16).map { b[4 + $0] ^ mask[$0] }
            return STUNAddress(ip: ipv6String(Data(raw)), port: port, isIPv6: true)
        } else {
            let raw = (0..<4).map { b[4 + $0] ^ cookieBytes[$0] }
            return STUNAddress(ip: raw.map(String.init).joined(separator: "."), port: port, isIPv6: false)
        }
    }

    // MARK: FINGERPRINT (CRC-32, RFC 5389 §15.5)

    /// Serialize with a trailing FINGERPRINT attribute computed per RFC 5389.
    public func encodedWithFingerprint() -> Data {
        var body = Data()
        for attr in attributes { Self.appendAttribute(&body, type: attr.type, value: attr.value) }
        // Length field must include the (8-byte) fingerprint attribute.
        let lengthWithFp = body.count + 8
        var msg = Self.header(method: method, cls: messageClass, length: lengthWithFp, txid: transactionID) + body
        let crc = CRC32.checksum(msg) ^ 0x5354_554E
        var fpVal = Data(); fpVal.appendBE(crc)
        Self.appendAttribute(&msg, type: Self.attrFingerprint, value: fpVal)
        return msg
    }

    public static func verifyFingerprint(_ msg: Data) -> Bool {
        guard msg.count >= 8 else { return false }
        // The fingerprint attribute is the last 8 bytes: type(0x8028)+len(4)+crc(4).
        let fpStart = msg.count - 8
        let stored = UInt32(bigEndian: msg.subdata(in: (msg.count - 4)..<msg.count).withUnsafeBytes { $0.load(as: UInt32.self) })
        let crc = CRC32.checksum(msg.subdata(in: 0..<fpStart)) ^ 0x5354_554E
        return stored == crc
    }

    // MARK: MESSAGE-INTEGRITY (HMAC-SHA1, RFC 5389 §15.4)

    /// Append a MESSAGE-INTEGRITY attribute keyed by `key` (short-term: the
    /// password bytes; long-term: MD5(username:realm:password)). Returns the full
    /// serialized message. Any attributes already present are included before it.
    public func encodedWithMessageIntegrity(key: Data) -> Data {
        var body = Data()
        for attr in attributes { Self.appendAttribute(&body, type: attr.type, value: attr.value) }
        // Length must include the (24-byte) MESSAGE-INTEGRITY attribute.
        let lengthWithMi = body.count + 24
        let partial = Self.header(method: method, cls: messageClass, length: lengthWithMi, txid: transactionID) + body
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: partial, using: SymmetricKey(data: key))
        var msg = partial
        Self.appendAttribute(&msg, type: Self.attrMessageIntegrity, value: Data(mac))
        return msg
    }

    // MARK: Decode

    public init?(decoding data: Data) {
        guard data.count >= 20 else { return nil }
        let b = [UInt8](data)
        let type = UInt16(b[0]) << 8 | UInt16(b[1])
        guard (type & 0xC000) == 0 else { return nil } // top 2 bits must be 0
        let (method, cls) = Self.unpackType(type)
        let length = Int(UInt16(b[2]) << 8 | UInt16(b[3]))
        let cookie = UInt32(b[4]) << 24 | UInt32(b[5]) << 16 | UInt32(b[6]) << 8 | UInt32(b[7])
        guard cookie == Self.magicCookie else { return nil }
        let txid = data.subdata(in: 8..<20)
        guard data.count >= 20 + length else { return nil }
        var attrs: [(UInt16, Data)] = []
        var i = 20
        let end = 20 + length
        while i + 4 <= end {
            let at = UInt16(b[i]) << 8 | UInt16(b[i + 1])
            let al = Int(UInt16(b[i + 2]) << 8 | UInt16(b[i + 3]))
            let vStart = i + 4
            guard vStart + al <= data.count else { break }
            attrs.append((at, data.subdata(in: vStart..<(vStart + al))))
            let padded = al + (4 - (al % 4)) % 4
            i = vStart + padded
        }
        self.init(messageClass: cls, method: method, transactionID: txid,
                  attributes: attrs.map { (type: $0.0, value: $0.1) })
    }

    // MARK: Address parsing helpers

    static func ipv4Bytes(_ s: String) -> Data? {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var d = Data()
        for p in parts { guard let n = UInt8(p) else { return nil }; d.append(n) }
        return d
    }
    static func ipv6Bytes(_ s: String) -> Data? {
        var addr = in6_addr()
        return s.withCString { inet_pton(AF_INET6, $0, &addr) == 1
            ? withUnsafeBytes(of: &addr) { Data($0) } : nil }
    }
    static func ipv6String(_ d: Data) -> String {
        var addr = in6_addr()
        _ = withUnsafeMutableBytes(of: &addr) { d.copyBytes(to: $0, count: min(16, d.count)) }
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(AF_INET6, &addr, &buf, socklen_t(INET6_ADDRSTRLEN))
        return String(cString: buf)
    }
}

// MARK: - CRC-32 (IEEE 802.3, for STUN FINGERPRINT)

enum CRC32 {
    static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Big-endian append helpers

extension Data {
    mutating func appendBE(_ v: UInt16) { append(UInt8(v >> 8)); append(UInt8(v & 0xFF)) }
    mutating func appendBE(_ v: UInt32) {
        append(UInt8((v >> 24) & 0xFF)); append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 8) & 0xFF)); append(UInt8(v & 0xFF))
    }
}
