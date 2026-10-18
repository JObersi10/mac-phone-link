// Guards the confirmed DCG auth wire-contract constants recovered from
// YourPhone.YPP.Auth.dll (docs/FINDINGS.md § "DCG auth + device identity").
// These pin the facts so a future refactor can't silently drift them.
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import DCGAuth

final class DCGWireContractTests: XCTestCase {

    func testAuthHostAndAuthority() {
        XCTAssertEqual(DCGWireContract.authHost.absoluteString,
                       "https://msatoken.dcg.microsoft.com")
        XCTAssertEqual(DCGWireContract.msaAuthority.absoluteString,
                       "https://login.microsoft.com/consumers")
    }

    func testRequestShape() {
        XCTAssertEqual(DCGWireContract.apiVersion, "2.0")
        XCTAssertEqual(DCGWireContract.apiVersionParam, "api-version")
        XCTAssertEqual(DCGWireContract.clientIdParam, "clientid")
    }

    func testMSAHeaders() {
        XCTAssertEqual(DCGWireContract.authorizationTypeHeader, "Authorization-Type")
        XCTAssertEqual(DCGWireContract.authorizationTypeMSA, "MSA")
        XCTAssertEqual(DCGWireContract.bearerPrefix, "Bearer ")
    }

    func testCryptoAlgorithms() {
        XCTAssertEqual(DCGWireContract.jwtSigningAlgorithmURI,
                       "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384")
        XCTAssertEqual(DCGWireContract.jweKeyWrapAlgorithm, "RSA-OAEP")
        XCTAssertEqual(DCGWireContract.jweContentEncryption, "A256CBC-HS512")
    }

    func testTrustTypesCoverPairingPaths() {
        let raw = Set(DCGWireContract.TrustType.allCases.map(\.rawValue))
        // The account-transfer / QR pairing paths must be representable.
        XCTAssertTrue(raw.isSuperset(of: ["A2D", "AccountPairingD2D", "AsyncD2D", "LegacyD2D"]))
    }
}
