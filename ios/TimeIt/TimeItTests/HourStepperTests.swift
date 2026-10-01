import XCTest
@testable import TimeIt

/// Activity Detail v3's hero stepper (owner ruling 2026-09-30): it MAY walk
/// past either end of the Range; outside it nothing is coloured and the pill
/// is the way back. `−` dims at the absolute WALKABLE lower bound.
///
/// The frames do not draw the out-of-Range or snap-back states (FIGMA.md §11
/// records them as "not yet drawn"), so the snap target follows the spec's
/// stated fallback: the NEAREST Range end.
final class HourStepperTests: XCTestCase {

    // Walk hours 0..<12; the Range covers 4..<8.
    private func stepper(selected: Int,
                         walkable: Range<Int> = 0..<12,
                         rangeHours: Range<Int>? = 4..<8) -> HourStepper {
        HourStepper(walkable: walkable, rangeHours: rangeHours, selected: selected)
    }

    // MARK: opening selection

    func testOpensOnTheRangesFirstHour() {
        XCTAssertEqual(HourStepper.initialSelection(walkable: 0..<12, rangeHours: 4..<8), 4)
    }

    func testOpensOnTheFirstWalkableHourWhenTheRangeHasNoneToday() {
        XCTAssertEqual(HourStepper.initialSelection(walkable: 3..<12, rangeHours: nil), 3)
    }

    // MARK: bounds — where the buttons dim

    func testMinusDimsAtTheWalkableLowerBoundNotTheRangeStart() {
        // At the Range start (4) the walk may still go back to 0.
        XCTAssertTrue(stepper(selected: 4).canStepBack)
        // Only the absolute walkable edge dims it.
        XCTAssertFalse(stepper(selected: 0).canStepBack)
    }

    func testPlusDimsAtTheWalkableUpperBound() {
        XCTAssertTrue(stepper(selected: 7).canStepForward)
        XCTAssertFalse(stepper(selected: 11).canStepForward)
    }

    func testStepsClampAtBothEnds() {
        var low = stepper(selected: 0)
        low.stepBack()
        XCTAssertEqual(low.selected, 0)

        var high = stepper(selected: 11)
        high.stepForward()
        XCTAssertEqual(high.selected, 11)
    }

    func testStepsWalkOneHourAtATimePastTheRange() {
        var s = stepper(selected: 4)
        s.stepBack()
        XCTAssertEqual(s.selected, 3)
        XCTAssertFalse(s.isInRange, "stepping below the Range leaves it")
        s.stepForward()
        XCTAssertEqual(s.selected, 4)
        XCTAssertTrue(s.isInRange)
    }

    func testInitialiserClampsAnUnreachableSelection() {
        XCTAssertEqual(stepper(selected: -5).selected, 0)
        XCTAssertEqual(stepper(selected: 99).selected, 11)
    }

    // MARK: in-range test — drives pill colouring and the uncoloured values

    func testIsInRangeAcrossBothRangeEdges() {
        XCTAssertFalse(stepper(selected: 3).isInRange)
        XCTAssertTrue(stepper(selected: 4).isInRange, "lower bound is inclusive")
        XCTAssertTrue(stepper(selected: 7).isInRange, "upper bound is exclusive — 7 is the last hour")
        XCTAssertFalse(stepper(selected: 8).isInRange)
    }

    func testNothingIsInRangeWhenTheRangeCoversNoHourToday() {
        XCTAssertFalse(stepper(selected: 5, rangeHours: nil).isInRange)
        XCTAssertFalse(stepper(selected: 5, rangeHours: 4..<4).isInRange,
                       "an empty range is treated as none")
    }

    // MARK: snap-back — the nearest Range end

    func testSnapTargetBelowTheRangeIsItsFirstHour() {
        XCTAssertEqual(stepper(selected: 0).snapBackTarget, 4)
        XCTAssertEqual(stepper(selected: 3).snapBackTarget, 4)
    }

    func testSnapTargetAboveTheRangeIsItsLastHour() {
        XCTAssertEqual(stepper(selected: 8).snapBackTarget, 7)
        XCTAssertEqual(stepper(selected: 11).snapBackTarget, 7)
    }

    func testNoSnapTargetWhileInsideTheRange() {
        XCTAssertNil(stepper(selected: 4).snapBackTarget)
        XCTAssertNil(stepper(selected: 6).snapBackTarget)
        XCTAssertNil(stepper(selected: 7).snapBackTarget)
    }

    func testNoSnapTargetWhenTheRangeHasNoHoursToday() {
        XCTAssertNil(stepper(selected: 5, rangeHours: nil).snapBackTarget)
    }

    func testSnapBackMovesTheSelectionAndIsIdempotent() {
        var s = stepper(selected: 11)
        s.snapBack()
        XCTAssertEqual(s.selected, 7)
        s.snapBack()
        XCTAssertEqual(s.selected, 7, "already in range — a no-op")
    }
}
