// Pairing module tests — QR grammar, proxy endpoints, ceremony ordering.
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import PhoneLinkPairing

final class PairingTests: XCTestCase {

    func testEncodesValidDynamicLinkURL() {
        let p = QRPairingPayload(uaid: "sess0001ABCD1234EF567890",
                                 traceId: "11111111-1111-1111-1111-111111111111")
        let s = p.encoded()
        XCTAssertTrue(s.hasPrefix("https://dcg.microsoft.com/?"), s)
        XCTAssertTrue(s.contains("vm=5"))
        XCTAssertTrue(s.contains("uaid=sess0001ABCD1234EF567890"))
        XCTAssertTrue(s.contains("ti=11111111-1111-1111-1111-111111111111"))
        XCTAssertTrue(s.contains("r=5"))
        XCTAssertTrue(s.contains("apn=com.microsoft.appmanager"))
        // Must be a URI with scheme AND host (what the scanner validates).
        let u = URL(string: s)
        XCTAssertEqual(u?.scheme, "https")
        XCTAssertEqual(u?.host, "dcg.microsoft.com")
    }

    func testParsesDynamicLinkURL() {
        let p = QRPairingPayload(parsing:
            "https://dcg-df.microsoft.com/?vm=5&uaid=XXXX1234567890ABCDEF&ti=abc&r=4&apn=com.microsoft.appmanager&tsft=T.token")
        XCTAssertEqual(p?.uaid, "XXXX1234567890ABCDEF")
        XCTAssertEqual(p?.environment, .dogfood)
        XCTAssertEqual(p?.ring, .beta)
        XCTAssertEqual(p?.mode, .idealFlow)
        XCTAssertEqual(p?.transferToken, "T.token")
    }

    func testRejectsBareQueryAndNonDCGHost() {
        // The old bad payload: no scheme / host → invalid.
        XCTAssertNil(QRPairingPayload(parsing: "uaid=maclink-15885620TKFWFGV9WFF00KQI"))
        // Wrong host → not a DCG dynamic link.
        XCTAssertNil(QRPairingPayload(parsing: "https://example.com/?uaid=abcdef&vm=5"))
    }

    func testYppPairingCodeIsLast16() {
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
        let p = QRPairingPayload(pairingCode: "ABCD1234EF567890", prefix: "sess01",
                                 traceId: "fixed-ti")
        XCTAssertEqual(p.yppPairingCode, "ABCD1234EF567890")
        let reparsed = QRPairingPayload(parsing: p.encoded())
        XCTAssertEqual(reparsed, p)
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
