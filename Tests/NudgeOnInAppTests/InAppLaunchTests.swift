import XCTest
@testable import NudgeOnInApp

final class InAppLaunchTests: XCTestCase {
    func testOwnerRecreationCannotClaimLaunchAgainButDifferentAppsCan() {
        let registry = InAppLaunchRegistry()
        XCTAssertTrue(registry.claim("app-a"))
        XCTAssertFalse(registry.claim("app-a"))
        XCTAssertTrue(registry.claim("app-b"))
        XCTAssertTrue(InAppLaunchRegistry().claim("app-a")) // a new process may try again
    }
    func testLateAuthorizationCannotPresentEvenIfTimerHasNotRun() {
        let window = InAppLaunchWindow(timeout: 3, now: 100)
        XCTAssertTrue(window.canPresent(now: 102.999))
        XCTAssertFalse(window.canPresent(now: 103))
        XCTAssertEqual(window.complete(.shown, now: 104), .timedOut)
        XCTAssertNil(window.complete(.failed, now: 105))
    }
    func testCancellationIsTerminalAndSuccessfulDisplayDoesNotLaterTimeOut() {
        let cancelled = InAppLaunchWindow(timeout: 3, now: 100)
        XCTAssertEqual(cancelled.complete(.cancelled, now: 101), .cancelled)
        XCTAssertFalse(cancelled.canPresent(now: 102))
        XCTAssertNil(cancelled.complete(.shown, now: 102))
        let shown = InAppLaunchWindow(timeout: 3, now: 100)
        XCTAssertEqual(shown.complete(.shown, now: 102), .shown)
        XCTAssertNil(shown.complete(.timedOut, now: 104))
    }
    func testInvalidTimeoutsRemainBounded() {
        XCTAssertEqual(InAppLaunchWindow(timeout: .nan, now: 10).deadline, 13)
        XCTAssertEqual(InAppLaunchWindow(timeout: -.infinity, now: 10).deadline, 13)
        XCTAssertEqual(InAppLaunchWindow(timeout: -10, now: 10).deadline, 11)
        XCTAssertEqual(InAppLaunchWindow(timeout: 10000, now: 10).deadline, 20)
    }
}
