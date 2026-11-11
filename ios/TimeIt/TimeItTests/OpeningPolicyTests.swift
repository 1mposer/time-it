import XCTest
@testable import TimeIt

/// The opening sequence's gate and timing (owner rulings 2026-11-11).
final class OpeningPolicyTests: XCTestCase {
    /// POLISH item 5: the bare first frame holds one extra second before the
    /// circles converge, so the app underneath mounts outside the springs.
    func testTheFirstFrameHoldsOneSecond() {
        XCTAssertEqual(OpeningPolicy.firstFrameHold, 1.0)
    }

    func testPlaysOnlyOnAColdLaunchWithNoPushRouteAndNoUITestSkip() {
        XCTAssertTrue(OpeningPolicy.shouldPlay(coldLaunch: true, pushRoutePending: false, uiTestSkip: false))
        XCTAssertFalse(OpeningPolicy.shouldPlay(coldLaunch: false, pushRoutePending: false, uiTestSkip: false))
        XCTAssertFalse(OpeningPolicy.shouldPlay(coldLaunch: true, pushRoutePending: true, uiTestSkip: false))
        XCTAssertFalse(OpeningPolicy.shouldPlay(coldLaunch: true, pushRoutePending: false, uiTestSkip: true))
    }

    func testTheEndFrameHoldIsOffOutsideAUITestRun() {
        XCTAssertFalse(OpeningPolicy.holdsEndFrame, "unit tests never pass UITEST_HOLD_OPENING")
    }
}
