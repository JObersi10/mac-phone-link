// Round-trip tests for the screen-mirroring / streaming clean-room models.
//
// SPDX-License-Identifier: MIT

import XCTest
import Foundation
@testable import PhoneLinkProtos

final class MirroringTests: XCTestCase {
    func testConfigRoundTrip() throws {
        var cfg = Maclink_Mirroring_V1_ConfigMessage()
        cfg.maxMainDisplayFps = 60
        cfg.width = 1080; cfg.height = 2340; cfg.dpi = 440
        cfg.hostDisplayWidth = 1920; cfg.hostDisplayHeight = 1080
        let parsed = try Maclink_Mirroring_V1_ConfigMessage(serializedBytes: cfg.serializedData())
        XCTAssertEqual(parsed, cfg)
    }

    func testLaunchAppOptionalFields() throws {
        var msg = Maclink_Mirroring_V1_LaunchAppMessage()
        msg.packageName = "com.example"
        msg.sessionID = "s1"
        msg.targetScreenLayout = 2
        msg.flags = 0x10
        let parsed = try Maclink_Mirroring_V1_LaunchAppMessage(serializedBytes: msg.serializedData())
        XCTAssertEqual(parsed, msg)
        XCTAssertTrue(parsed.hasTargetScreenLayout)
        XCTAssertFalse(parsed.hasTransferTaskID)
    }

    func testStreamingConfigRoundTrip() throws {
        var cfg = Maclink_Streaming_V1_StreamingConfigurationMessage()
        cfg.isCapable = 1
        cfg.permissionsGranted = 1
        cfg.permissionsPermanentlyDenied = false
        let parsed = try Maclink_Streaming_V1_StreamingConfigurationMessage(serializedBytes: cfg.serializedData())
        XCTAssertEqual(parsed, cfg)
    }
}
