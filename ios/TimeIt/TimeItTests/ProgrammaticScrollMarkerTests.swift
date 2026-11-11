import XCTest
@testable import TimeIt

/// Build-8 deferral (9): a stale programmatic-scroll target after an
/// interrupted `scroll(to:)` must never swallow a later selection haptic.
final class ProgrammaticScrollMarkerTests: XCTestCase {

    func testTheArrivalIsProgrammaticAndConsumesTheMarker() {
        var marker = ProgrammaticScrollMarker()
        marker.set(7)

        XCTAssertTrue(marker.consume(7), "the scroll's own arrival — no tick")
        XCTAssertNil(marker.target)
        XCTAssertFalse(marker.consume(7), "a second landing on 7 is the user's")
    }

    func testAnInterruptedScrollNeverLeavesAStaleTarget() {
        var marker = ProgrammaticScrollMarker()
        marker.set(7)

        XCTAssertFalse(marker.consume(4), "the user's drag interrupted the scroll — a user move")
        XCTAssertFalse(marker.consume(7),
                       "the user later lands on the old target: it ticks (the build-8 bug swallowed it)")
    }

    func testNoMarkerMeansEveryChangeIsTheUsers() {
        var marker = ProgrammaticScrollMarker()

        XCTAssertFalse(marker.consume(3))
        XCTAssertFalse(marker.consume(nil))
    }
}
