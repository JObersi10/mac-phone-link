import XCTest
@testable import Companion

private final class FakeTransport: CompanionTransport {
    var sentLines: [Data] = []
    func send(_ line: Data) async throws { sentLines.append(line) }
}

final class CompanionTests: XCTestCase {
    func testRingPhoneSerializesFindMyPhoneRequest() async throws {
        let transport = FakeTransport()
        let client = CompanionClient(transport: transport)
        try await client.ringPhone()

        XCTAssertEqual(transport.sentLines.count, 1)
        let line = transport.sentLines[0]
        XCTAssertEqual(line.last, 0x0a) // newline terminated
        let header = try JSONDecoder().decode(PacketHeader.self, from: line)
        XCTAssertEqual(header.type, CompanionPacketType.findMyPhoneRequest)
    }

    func testMediaCommandSerializesAction() async throws {
        let transport = FakeTransport()
        let client = CompanionClient(transport: transport)
        try await client.mediaCommand(player: "Apple Music", action: "PlayPause")

        let body = try JSONDecoder()
            .decode(NetworkPacket<MprisRequestBody>.self, from: transport.sentLines[0]).body
        XCTAssertEqual(body.player, "Apple Music")
        XCTAssertEqual(body.action, "PlayPause")
    }

    func testHandleRoutesNotification() throws {
        final class Spy: CompanionDelegate {
            var received: NotificationBody?
            func companionDidReceiveNotification(_ n: NotificationBody) { received = n }
        }
        let spy = Spy()
        let client = CompanionClient(transport: FakeTransport())
        client.delegate = spy

        let packet = NetworkPacket(type: CompanionPacketType.notification,
                                   body: NotificationBody(id: "1", appName: "Discord",
                                                          title: "Water Niko",
                                                          text: "Reacted to you",
                                                          ticker: nil, isClearable: true,
                                                          silent: nil, time: nil, isCancel: nil))
        client.handle(line: try packet.serializedLine())
        XCTAssertEqual(spy.received?.appName, "Discord")
        XCTAssertEqual(spy.received?.title, "Water Niko")
    }

    func testHandleRoutesMedia() throws {
        final class Spy: CompanionDelegate {
            var media: MprisBody?
            func companionDidUpdateMedia(_ m: MprisBody) { media = m }
        }
        let spy = Spy()
        let client = CompanionClient(transport: FakeTransport())
        client.delegate = spy

        let packet = NetworkPacket(type: CompanionPacketType.mpris,
                                   body: MprisBody(player: "Apple Music", title: "Lift Me Up",
                                                   artist: "HILLS", album: nil, isPlaying: true,
                                                   canPause: true, canPlay: true, canGoNext: true,
                                                   canGoPrevious: true, length: nil, pos: nil,
                                                   volume: nil, albumArtUrl: nil, playerList: nil))
        client.handle(line: try packet.serializedLine())
        XCTAssertEqual(spy.media?.title, "Lift Me Up")
        XCTAssertEqual(spy.media?.isPlaying, true)
    }

    // MARK: - Crypto

    func testCryptoRoundTrip() throws {
        let crypto = CompanionCrypto(key: CompanionCrypto.generateKey())
        let plaintext = Data(#"{"type":"kdeconnect.ping","body":{}}"#.utf8)
        let sealed = try crypto.seal(plaintext)
        XCTAssertNotEqual(sealed, plaintext)
        XCTAssertEqual(try crypto.open(sealed), plaintext)
    }

    func testCryptoBase64FrameRoundTrip() throws {
        let crypto = CompanionCrypto(key: CompanionCrypto.generateKey())
        let plaintext = Data("hello companion".utf8)
        let frame = try crypto.sealToBase64(plaintext)
        XCTAssertEqual(try crypto.openFromBase64(frame), plaintext)
    }

    func testCryptoKeyBase64RoundTrips() throws {
        let original = CompanionCrypto(key: CompanionCrypto.generateKey())
        let restored = CompanionCrypto(base64Key: original.base64Key)
        XCTAssertNotNil(restored)
        let plaintext = Data("shared key works".utf8)
        let sealed = try original.seal(plaintext)
        XCTAssertEqual(try restored?.open(sealed), plaintext)
    }

    func testCryptoRejectsBadKeyLength() {
        XCTAssertNil(CompanionCrypto(base64Key: Data("too short".utf8).base64EncodedString()))
        XCTAssertNil(CompanionCrypto(base64Key: "not base64 @@@"))
    }

    func testCryptoOpenRejectsGarbage() {
        let crypto = CompanionCrypto(key: CompanionCrypto.generateKey())
        XCTAssertThrowsError(try crypto.openFromBase64("###"))
    }

    // MARK: - Pairing code

    func testPairingCodeRoundTrip() throws {
        let key = CompanionCrypto(key: CompanionCrypto.generateKey()).base64Key
        let code = PairingCode(host: "192.168.1.42", port: 8787, name: "Johns Mac", base64Key: key)
        let parsed = try XCTUnwrap(PairingCode(parsing: code.encoded()))
        XCTAssertEqual(parsed.host, "192.168.1.42")
        XCTAssertEqual(parsed.port, 8787)
        XCTAssertEqual(parsed.name, "Johns Mac")
        XCTAssertEqual(parsed.base64Key, key) // base64 '+' / '=' survive the URL round-trip
    }

    func testPairingCodeRejectsWrongScheme() {
        XCTAssertNil(PairingCode(parsing: "https://192.168.1.42:8787?key=abc"))
        XCTAssertNil(PairingCode(parsing: "maclink://192.168.1.42:8787")) // no key
    }
}
