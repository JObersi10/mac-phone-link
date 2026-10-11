// Tests for the onboarding flow logic (step navigation, injected sign-in) and
// QR generation. UI rendering and real permission prompts are not exercised.
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import PhoneLinkUI

@MainActor
final class OnboardingTests: XCTestCase {
    private func makeModel() -> OnboardingViewModel {
        OnboardingViewModel(permissions: PermissionsManager(), pairingPayload: "ms-phone-link://pair?v=1")
    }

    func testStepNavigation() {
        let m = makeModel()
        XCTAssertEqual(m.step, .welcome)
        m.next(); XCTAssertEqual(m.step, .permissions)
        m.next(); XCTAssertEqual(m.step, .signIn)
        m.back(); XCTAssertEqual(m.step, .permissions)
        // clamp at ends
        m.back(); m.back(); XCTAssertEqual(m.step, .welcome)
    }

    func testSignInInjectionSuccess() async {
        let m = makeModel()
        m.signInAction = { "ada@example.com" }
        await m.signIn()
        XCTAssertEqual(m.signedInUser, "ada@example.com")
        XCTAssertTrue(m.isSignedIn)
        XCTAssertNil(m.signInError)
    }

    func testSignInMissingActionReportsError() async {
        let m = makeModel()
        await m.signIn()
        XCTAssertFalse(m.isSignedIn)
        XCTAssertNotNil(m.signInError)
    }

    func testSignInFailureSurfacesError() async {
        struct E: Error {}
        let m = makeModel()
        m.signInAction = { throw E() }
        await m.signIn()
        XCTAssertNil(m.signedInUser)
        XCTAssertNotNil(m.signInError)
    }

    func testFinishReachesDone() {
        let m = makeModel()
        var finished = false
        m.onFinish = { finished = true }
        for _ in OnboardingViewModel.Step.allCases { m.next() }
        XCTAssertEqual(m.step, .done)
        XCTAssertTrue(finished)
    }

    #if canImport(AppKit)
    func testQRImageNonNil() {
        XCTAssertNotNil(QRCode.image(from: "ms-phone-link://pair?v=1"))
        XCTAssertNil(QRCode.image(from: ""))
    }
    #endif
}
