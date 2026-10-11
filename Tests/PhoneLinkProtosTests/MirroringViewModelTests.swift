// MirroringViewModel tests — initial state + loopback self-test path.
//
// SPDX-License-Identifier: MIT

import XCTest
import NanoTransport
@testable import PhoneLinkUI

@MainActor
final class MirroringViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = MirroringViewModel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.framesReceived, 0)
        XCTAssertFalse(vm.isActive)
    }

    func testDemoLoopbackDeliversOneFrame() async {
        let vm = MirroringViewModel()
        vm.connect(host: "", port: 0)   // empty host → loopback self-test
        // onFrame/onStateChange hop through Task { @MainActor }; let them run.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(vm.framesReceived, 1)
    }

    func testDisconnectResetsState() async {
        let vm = MirroringViewModel()
        vm.connect(host: "", port: 0)
        for _ in 0..<20 { await Task.yield() }
        vm.disconnect()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isActive)
    }
}
