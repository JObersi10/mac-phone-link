// Tests for the ICE/STUN core of the Nano transport.
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import NanoTransport

final class ICESTUNTests: XCTestCase {

    // MARK: STUN message type packing

    func testMessageTypePacking() {
        XCTAssertEqual(STUNMessage.packType(method: STUNMessage.methodBinding, cls: .request), 0x0001)
        XCTAssertEqual(STUNMessage.packType(method: STUNMessage.methodBinding, cls: .successResponse), 0x0101)
        let (m, c) = STUNMessage.unpackType(0x0101)
        XCTAssertEqual(m, STUNMessage.methodBinding)
        XCTAssertEqual(c, .successResponse)
    }

    // MARK: Header + attribute round-trip

    func testEncodeDecodeRoundTrip() throws {
        var msg = STUNMessage(messageClass: .request)
        msg.attributes.append((STUNMessage.attrUsername, Data("alice:bob".utf8)))
        let data = msg.encoded()
        let decoded = try XCTUnwrap(STUNMessage(decoding: data))
        XCTAssertEqual(decoded.messageClass, .request)
        XCTAssertEqual(decoded.method, STUNMessage.methodBinding)
        XCTAssertEqual(decoded.transactionID, msg.transactionID)
        XCTAssertEqual(decoded.attributes.first?.type, STUNMessage.attrUsername)
        XCTAssertEqual(decoded.attributes.first?.value, Data("alice:bob".utf8))
    }

    func testAttributePadding() throws {
        // A 3-byte value must be padded to 4 and decode back to exactly 3 bytes.
        var msg = STUNMessage(messageClass: .indication)
        msg.attributes.append((0x7FFF, Data([1, 2, 3])))
        let decoded = try XCTUnwrap(STUNMessage(decoding: msg.encoded()))
        XCTAssertEqual(decoded.attributes.first?.value, Data([1, 2, 3]))
    }

    // MARK: XOR-MAPPED-ADDRESS

    func testXorMappedAddressIPv4RoundTrip() throws {
        var msg = STUNMessage(messageClass: .successResponse)
        let addr = STUNAddress(ip: "192.0.2.1", port: 32853, isIPv6: false)
        msg.addXorMappedAddress(addr)
        let decoded = try XCTUnwrap(STUNMessage(decoding: msg.encoded()))
        XCTAssertEqual(decoded.xorMappedAddress(), addr)
    }

    func testXorMappedAddressIsActuallyXored() {
        // Port 32853 (0x8055) XOR 0x2112 = 0xA147 — the stored bytes must differ
        // from the plaintext port, proving the XOR happened.
        let addr = STUNAddress(ip: "192.0.2.1", port: 32853, isIPv6: false)
        let txid = STUNMessage.newTransactionID()
        let v = STUNMessage.encodeXorMappedAddress(addr, transactionID: txid)
        XCTAssertEqual(v[2], 0xA1)
        XCTAssertEqual(v[3], 0x47)
    }

    // MARK: FINGERPRINT

    func testFingerprintVerifies() {
        var msg = STUNMessage(messageClass: .request)
        msg.attributes.append((STUNMessage.attrUsername, Data("x:y".utf8)))
        let withFp = msg.encodedWithFingerprint()
        XCTAssertTrue(STUNMessage.verifyFingerprint(withFp))
        // Flip a byte in the body -> verification fails.
        var tampered = withFp
        tampered[21] ^= 0xFF
        XCTAssertFalse(STUNMessage.verifyFingerprint(tampered))
    }

    // MARK: ICE candidate priority (RFC 8445)

    func testHostCandidateHasHighestPriority() {
        let host = ICECandidate(foundation: "1", type: .host,
                                address: STUNAddress(ip: "10.0.0.2", port: 5000, isIPv6: false))
        let relay = ICECandidate(foundation: "2", type: .relayed,
                                 address: STUNAddress(ip: "203.0.113.9", port: 6000, isIPv6: false))
        XCTAssertGreaterThan(host.priority(), relay.priority())
        // Type preference lives in the top byte: host=126.
        XCTAssertEqual(host.priority() >> 24, 126)
        XCTAssertEqual(relay.priority() >> 24, 0)
    }

    func testCandidateTypeRawValuesMatchBinary() {
        XCTAssertEqual(ICECandidateType.host.rawValue, 0)
        XCTAssertEqual(ICECandidateType.serverReflexive.rawValue, 1)
        XCTAssertEqual(ICECandidateType.peerReflexive.rawValue, 2)
        XCTAssertEqual(ICECandidateType.relayed.rawValue, 3)
        XCTAssertEqual(ICECandidateType.manual.rawValue, 4)
    }

    // MARK: ICE agent

    func testGatherHostCandidatesReturnsSomething() {
        let agent = ICEAgent(isControlling: true)
        let cands = agent.gatherHostCandidates(port: 50000)
        // CI runners always have at least one non-loopback interface.
        XCTAssertFalse(cands.isEmpty)
        XCTAssertTrue(cands.allSatisfy { $0.type == .host && $0.address.port == 50000 })
    }

    func testChecklistOrderedByPriority() {
        let agent = ICEAgent(isControlling: true,
                             localCredentials: ICECredentials(ufrag: "loca", password: "localpassword0000000000"))
        let local = [
            ICECandidate(foundation: "1", type: .host,
                         address: STUNAddress(ip: "10.0.0.2", port: 5000, isIPv6: false)),
            ICECandidate(foundation: "2", type: .relayed,
                         address: STUNAddress(ip: "203.0.113.1", port: 7000, isIPv6: false)),
        ]
        let remote = [
            ICECandidate(foundation: "9", type: .host,
                         address: STUNAddress(ip: "10.0.0.3", port: 5001, isIPv6: false)),
        ]
        let checklist = agent.formChecklist(local: local, remote: remote)
        XCTAssertEqual(checklist.count, 2)
        XCTAssertEqual(checklist.first?.local.type, .host)   // host pair ranks first
        XCTAssertEqual(checklist.first?.state, .waiting)
    }

    func testConnectivityCheckIsValidStunWithFingerprint() throws {
        let agent = ICEAgent(isControlling: true,
                             localCredentials: ICECredentials(ufrag: "loca", password: "localpwd00000000000000"))
        agent.remoteCredentials = ICECredentials(ufrag: "remo", password: "remotepwd0000000000000")
        let pair = ICECandidatePair(
            local: ICECandidate(foundation: "1", type: .host,
                                address: STUNAddress(ip: "10.0.0.2", port: 5000, isIPv6: false)),
            remote: ICECandidate(foundation: "9", type: .host,
                                 address: STUNAddress(ip: "10.0.0.3", port: 5001, isIPv6: false)))
        let check = try XCTUnwrap(agent.buildConnectivityCheck(for: pair, useCandidate: true))
        XCTAssertTrue(STUNMessage.verifyFingerprint(check))
        let decoded = try XCTUnwrap(STUNMessage(decoding: check))
        XCTAssertEqual(decoded.messageClass, .request)
        XCTAssertTrue(decoded.attributes.contains { $0.type == STUNMessage.attrUsername })
        XCTAssertTrue(decoded.attributes.contains { $0.type == STUNMessage.attrPriority })
        XCTAssertTrue(decoded.attributes.contains { $0.type == STUNMessage.attrIceControlling })
        XCTAssertTrue(decoded.attributes.contains { $0.type == STUNMessage.attrUseCandidate })
        XCTAssertTrue(decoded.attributes.contains { $0.type == STUNMessage.attrMessageIntegrity })
    }

    func testCheckSucceedsWhenPeerAnswers() async throws {
        let agent = ICEAgent(isControlling: true,
                             localCredentials: ICECredentials(ufrag: "loca", password: "localpwd00000000000000"))
        agent.remoteCredentials = ICECredentials(ufrag: "remo", password: "remotepwd0000000000000")
        let pair = ICECandidatePair(
            local: ICECandidate(foundation: "1", type: .host,
                                address: STUNAddress(ip: "10.0.0.2", port: 5000, isIPv6: false)),
            remote: ICECandidate(foundation: "9", type: .host,
                                 address: STUNAddress(ip: "10.0.0.3", port: 5001, isIPv6: false)))
        let ok = await agent.check(pair, over: EchoSuccessChecker())
        XCTAssertTrue(ok)
    }
}

/// A STUNChecker that answers each binding request with a success response
/// carrying the same transaction id (as a cooperating peer would).
private struct EchoSuccessChecker: STUNChecker {
    func sendBindingRequest(_ request: Data, to address: STUNAddress) async throws -> Data {
        let req = STUNMessage(decoding: request)!
        var resp = STUNMessage(messageClass: .successResponse,
                               method: STUNMessage.methodBinding,
                               transactionID: req.transactionID)
        resp.addXorMappedAddress(address)
        return resp.encodedWithFingerprint()
    }
}
