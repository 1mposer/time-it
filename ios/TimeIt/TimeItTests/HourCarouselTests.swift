import XCTest
@testable import TimeIt

/// The detail hero carousel (depth & polish pass, build 8 — owner rulings
/// 2026-10-31 / 2026-11-01): the whole Range-length span slides one hour per
/// − / +, and the visible window keeps exactly one slot of lookahead beyond
/// the span's leading edge until the day's end is in view.
///
/// Every expected `firstVisible` below is hand-derived from the two rules
/// (clamped to `walkable.lowerBound ... walkable.upperBound − visibleSlots`):
///   forward: f = max(f, lastHour + 2 − V)
///   back:    f = min(f, firstHour − 1)
/// and, when the span is at least as long as the window (`L ≥ V`):
///   f = firstHour (one-slot lookahead cannot hold, so the window anchors on
///   the span's start).
final class HourCarouselTests: XCTestCase {

    // A 16-hour day (walkable 0..<16) with a 4-hour Range 4..<8 and 5 slots.
    private func fourHour() -> HourCarousel {
        HourCarousel(walkable: 0..<16, rangeHours: 4..<8, visibleSlots: 5)
    }

    // MARK: Opening state

    func testOpensWithTheSpanOnTheRangeAndTheRangeAtTheWindowsLeft() {
        let c = fourHour()
        XCTAssertEqual(c.span, 4..<8)
        XCTAssertTrue(c.isAtRange)
        XCTAssertFalse(c.canReturnToRange)
        // f = clamp(4) = 4 → visible 4..<9: the Range in slots 0–3, one
        // lookahead slot (8) on the right.
        XCTAssertEqual(c.firstVisible, 4)
        XCTAssertEqual(c.visible, 4..<9)
    }

    func testALateRangeOpensClampedToTheDaysEnd() {
        // Range 12..<16 ends the day: f = clamp(12) to ≤ 16 − 5 = 11.
        let c = HourCarousel(walkable: 0..<16, rangeHours: 12..<16, visibleSlots: 5)
        XCTAssertEqual(c.firstVisible, 11)
        XCTAssertFalse(c.canStepForward)
    }

    func testNoRangeTodayGivesAOneHourSpanAtTheWalkStartAndNoReturn() {
        let c = HourCarousel(walkable: 3..<12, rangeHours: nil, visibleSlots: 4)
        XCTAssertEqual(c.span, 3..<4)
        XCTAssertFalse(c.isAtRange)
        XCTAssertFalse(c.canReturnToRange, "nothing to return to")
        XCTAssertFalse(c.overlapsRange)
        XCTAssertEqual(c.firstVisible, 3)
    }

    func testVisibleSlotsAreCappedAtTheWalkableCount() {
        let c = HourCarousel(walkable: 0..<3, rangeHours: 0..<2, visibleSlots: 5)
        XCTAssertEqual(c.visibleSlots, 3)
        XCTAssertEqual(c.firstVisible, 0)
    }

    // MARK: Bounds — where − / + dim

    func testMinusDimsWhenTheSpanStartsAtTheWalkStart() {
        var c = fourHour()
        XCTAssertTrue(c.canStepBack, "the Range start is not the walk start")
        for _ in 0..<4 { c.stepBack() }
        XCTAssertEqual(c.span, 0..<4)
        XCTAssertFalse(c.canStepBack)
        c.stepBack()
        XCTAssertEqual(c.span, 0..<4, "clamped — a fifth press is a no-op")
    }

    func testPlusDimsWhenTheSpanEndsAtTheWalkEnd() {
        var c = fourHour()
        for _ in 0..<8 { c.stepForward() }
        XCTAssertEqual(c.span, 12..<16)
        XCTAssertFalse(c.canStepForward)
        c.stepForward()
        XCTAssertEqual(c.span, 12..<16, "clamped")
    }

    func testTheSpanKeepsTheRangeLengthWhileSliding() {
        var c = fourHour()
        c.stepForward()
        XCTAssertEqual(c.span, 5..<9)
        c.stepBack()
        c.stepBack()
        XCTAssertEqual(c.span, 3..<7)
    }

    // MARK: Lookahead window — 4-hour Range, 16-hour day, 5 slots

    func testForwardWindowSequenceForAFourHourRange() {
        // span 5..<9 → max(4, 8+2−5=5)=5; 6..<10 → 6; 7 → 7; 8 → 8; 9 → 9;
        // 10 → 10; 11..<15 → 11; 12..<16 → max(11,12)=12 → clamp 11.
        var c = fourHour()
        var seen: [Int] = []
        while c.canStepForward { c.stepForward(); seen.append(c.firstVisible) }
        XCTAssertEqual(seen, [5, 6, 7, 8, 9, 10, 11, 11])
        // The day's last hour is in view, and the span ends there.
        XCTAssertEqual(c.visible.upperBound, 16)
    }

    func testBackWindowSequenceForAFourHourRange() {
        // span 3..<7 → min(4, 3−1=2)=2 (the one-spare-slot jump: the Range
        // opened at the window's left, so the lookback slot costs two);
        // 2..<6 → 1; 1..<5 → 0; 0..<4 → min(0,−1) → clamp 0.
        var c = fourHour()
        var seen: [Int] = []
        while c.canStepBack { c.stepBack(); seen.append(c.firstVisible) }
        XCTAssertEqual(seen, [2, 1, 0, 0])
    }

    func testTheWindowHoldsStillWhileTheLeadingEdgeHasLookahead() {
        // A 2-hour Range in 4 slots: f opens at 4 (visible 4..<8). Span 5..<7
        // has last hour 6 = slot 2 = the second-to-last slot → max(4, 6+2−4=4)
        // = 4: no move yet. Span 6..<8 → max(4,5)=5: now it moves.
        var c = HourCarousel(walkable: 0..<16, rangeHours: 4..<6, visibleSlots: 4)
        c.stepForward()
        XCTAssertEqual(c.firstVisible, 4, "edge on the second-to-last slot — window still")
        c.stepForward()
        XCTAssertEqual(c.firstVisible, 5, "edge would pass it — window shifts one")
        // Reversing: span 5..<7 → min(5, 4) = 4.
        c.stepBack()
        XCTAssertEqual(c.firstVisible, 4)
        // Span 4..<6 → min(4, 3) = 3.
        c.stepBack()
        XCTAssertEqual(c.firstVisible, 3)
    }

    func testReversingAfterForwardRestoresTheLookbackSlot() {
        // + + → span 6..<10, f 6. − → span 5..<9, f = min(6, 4) = 4.
        var c = fourHour()
        c.stepForward(); c.stepForward()
        XCTAssertEqual(c.firstVisible, 6)
        c.stepBack()
        XCTAssertEqual(c.firstVisible, 4)
    }

    // MARK: 8-hour Range — longer than the default 4 slots

    func testEightHourRangeWithNineSlots() {
        // V = 8 + 1 = 9; f opens clamp(4) to ≤ 16 − 9 = 7 → 4.
        // Forward: 5..<13 → max(4, 12+2−9=5)=5; 6; 7; 8..<16 → 8 → clamp 7.
        var forward = HourCarousel(walkable: 0..<16, rangeHours: 4..<12, visibleSlots: 9)
        XCTAssertEqual(forward.firstVisible, 4)
        var seen: [Int] = []
        while forward.canStepForward { forward.stepForward(); seen.append(forward.firstVisible) }
        XCTAssertEqual(seen, [5, 6, 7, 7])

        // Back: 3..<11 → min(4, 2)=2; 2..<10 → 1; 1..<9 → 0; 0..<8 → 0.
        var back = HourCarousel(walkable: 0..<16, rangeHours: 4..<12, visibleSlots: 9)
        seen = []
        while back.canStepBack { back.stepBack(); seen.append(back.firstVisible) }
        XCTAssertEqual(seen, [2, 1, 0, 0])
    }

    func testASpanLongerThanTheWindowAnchorsOnItsFirstHour() {
        // The 22pt floor capped V at 6 under an 8-hour span: f = span start,
        // clamped to ≤ 16 − 6 = 10. Forward 5,6,7,8; back from open 3,2,1,0.
        var forward = HourCarousel(walkable: 0..<16, rangeHours: 4..<12, visibleSlots: 6)
        XCTAssertEqual(forward.firstVisible, 4)
        var seen: [Int] = []
        while forward.canStepForward { forward.stepForward(); seen.append(forward.firstVisible) }
        XCTAssertEqual(seen, [5, 6, 7, 8])

        var back = HourCarousel(walkable: 0..<16, rangeHours: 4..<12, visibleSlots: 6)
        seen = []
        while back.canStepBack { back.stepBack(); seen.append(back.firstVisible) }
        XCTAssertEqual(seen, [3, 2, 1, 0])
    }

    // MARK: Return to range

    func testReturnToRangeRestoresTheSpanAndTheOpeningWindow() {
        var c = fourHour()
        let opening = c
        for _ in 0..<6 { c.stepForward() }
        XCTAssertFalse(c.isAtRange)
        XCTAssertTrue(c.canReturnToRange)
        c.returnToRange()
        XCTAssertEqual(c, opening)
        XCTAssertTrue(c.isAtRange)
        XCTAssertFalse(c.canReturnToRange)

        for _ in 0..<3 { c.stepBack() }
        c.returnToRange()
        XCTAssertEqual(c, opening)
    }

    func testIsAtRangeOnlyOnTheExactRange() {
        var c = fourHour()
        c.stepForward()
        XCTAssertFalse(c.isAtRange, "an overlapping span is not the Range")
        XCTAssertTrue(c.overlapsRange)
        c.stepBack()
        XCTAssertTrue(c.isAtRange)
    }

    func testOverlapEndsOnceTheSpanLeavesTheRange() {
        var c = fourHour()
        for _ in 0..<3 { c.stepForward() }
        XCTAssertTrue(c.overlapsRange, "7..<11 still shares hour 7")
        c.stepForward()
        XCTAssertFalse(c.overlapsRange, "8..<12 is entirely past the Range")
    }

    func testSwipeStepsByWholeHours() {
        var c = fourHour()
        c.step(by: 3)
        XCTAssertEqual(c.span, 7..<11)
        c.step(by: -20)
        XCTAssertEqual(c.span, 0..<4, "a long swipe clamps at the walk start")
    }

    // MARK: Visible-slot count (owner-tunable)

    func testVisibleSlotCountIsRangePlusOneWithAFloorOfFour() {
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 222), 5)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 2, availableWidth: 222), 4)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 1, availableWidth: 222), 4)
    }

    func testVisibleSlotCountNeverMakesAPillNarrowerThan22pt() {
        // floor((222 + 3) / (22 + 3)) = 9 pills fit.
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 8, availableWidth: 222), 9)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 12, availableWidth: 222), 9)
        // floor((120 + 3) / 25) = 4.
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 120), 4)
    }

    func testVisibleSlotCountBeforeLayoutUsesTheWantedCount() {
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 0), 5)
    }
}
