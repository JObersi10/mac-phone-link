// Pairing module tests — QR grammar, proxy endpoints, ceremony ordering.
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import PhoneLinkPairing

final class PairingTests: XCTestCase {

    func testParsesUaidAndCode() {
        let p = QRPairingPayload(parsing: "uaid=00000000ABCD1234EF567890&code=M.R3_BAY.abc123")
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.uaid, "00000000ABCD1234EF567890")
        XCTAssertEqual(p?.msaCode, "M.R3_BAY.abc123")
    }

    func testParsesFromFullURI() {
        let p = QRPairingPayload(parsing: "ms-phone-link://pair?uaid=XXXX1234567890ABCDEF&code=zzz")
        XCTAssertEqual(p?.uaid, "XXXX1234567890ABCDEF")
        XCTAssertEqual(p?.msaCode, "zzz")
    }

    func testYppPairingCodeIsLast16() {
        // 8-char prefix + 16-char code.
        let p = QRPairingPayload(uaid: "PREFIX00ABCD1234EF567890")
        XCTAssertEqual(p.uaid.count, 24)
        XCTAssertEqual(p.yppPairingCode, "ABCD1234EF567890")
        XCTAssertEqual(p.yppPairingCode?.count, 16)
    }

    func testShortUaidHasNoPairingCode() {
        XCTAssertNil(QRPairingPayload(uaid: "SHORT").yppPairingCode)
        XCTAssertNil(QRPairingPayload(uaid: "EXACTLY16CHARSXX").yppPairingCode) // == 16, not > 16
    }

    func testPrefixMeaningfulness() {
        XCTAssertFalse(QRPairingPayload(uaid: "0000000000000000ABCD1234EF567890").hasMeaningfulPrefix)
        XCTAssertTrue(QRPairingPayload(uaid: "sess1234ABCD1234EF567890").hasMeaningfulPrefix)
    }

    func testBuildFromPairingCodeRoundTrips() {
        let p = QRPairingPayload(pairingCode: "ABCD1234EF567890", prefix: "sess01", msaCode: "M.code")
        XCTAssertEqual(p.yppPairingCode, "ABCD1234EF567890")
        let reparsed = QRPairingPayload(parsing: p.encoded())
        XCTAssertEqual(reparsed, p)
    }

    func testEncodeOmitsMissingCode() {
        XCTAssertEqual(QRPairingPayload(uaid: "abc").encoded(), "uaid=abc")
    }

    func testEndpointsUnderDCGHost() {
        let ep = PairingProxyEndpoints(environment: .production)
        XCTAssertEqual(ep.createPinSession(id: "S1").absoluteString,
                       "https://dcg.microsoft.com/DevicePairingProxy/PinSessions/S1")
        XCTAssertEqual(ep.pinSessionQRScanned(id: "S1").absoluteString,
                       "https://dcg.microsoft.com/DevicePairingProxy/PinSessions/S1/QRScanned")
        XCTAssertEqual(ep.pairingSessionComplete(id: "P9").absoluteString,
                       "https://dcg.microsoft.com/DevicePairingProxy/PairingSessions/P9/Complete")
    }

    func testEnvironmentHosts() {
        XCTAssertEqual(DCGEnvironment.dogfood.host, "dcg-df.microsoft.com")
        XCTAssertEqual(DCGEnvironment.beta.host, "dcg-beta.microsoft.com")
    }

    func testCeremonyAdvancesInOrder() {
        var c = PairingCeremony()
        XCTAssertEqual(c.state, .checkPermission)
        var seen: [PairingCeremonyState] = [c.state]
        while c.advance() { seen.append(c.state) }
        XCTAssertEqual(seen, [
            .checkPermission, .getChannelInfo, .openConnection, .joinChannel,
            .sendDeviceInfo, .sendCryptoInfo, .sendNonce, .waitForPing,
            .commitCryptoTrust, .succeeded,
        ])
        XCTAssertTrue(c.isTerminal)
    }

    func testCeremonyFailIsTerminal() {
        var c = PairingCeremony()
        c.fail()
        XCTAssertEqual(c.state, .failed)
        XCTAssertFalse(c.advance())
    }
}
