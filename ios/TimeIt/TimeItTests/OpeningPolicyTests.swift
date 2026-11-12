import XCTest
@testable import TimeIt

/// The opening sequence's gate and timing (owner rulings 2026-11-11; Q2b
/// 2026-11-12: the full opening on the first launch only, a plain fade after).
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

    func testTheFirstLaunchPlaysTheFullOpening() {
        XCTAssertEqual(OpeningPolicy.mode(plays: true, hasSeenOpening: false), .converge)
    }

    func testEveryLaterLaunchIsAPlainFade() {
        XCTAssertEqual(OpeningPolicy.mode(plays: true, hasSeenOpening: true), .fade)
    }

    func testALaunchThatDoesNotOpenShowsNothingEitherWay() {
        XCTAssertEqual(OpeningPolicy.mode(plays: false, hasSeenOpening: false), .none)
        XCTAssertEqual(OpeningPolicy.mode(plays: false, hasSeenOpening: true), .none)
    }

    func testTheEndFrameHoldIsOffOutsideAUITestRun() {
        XCTAssertFalse(OpeningPolicy.holdsEndFrame, "unit tests never pass UITEST_HOLD_OPENING")
    }
}
