import XCTest
@testable import TimeIt

/// The detail hero carousel (depth & polish pass, build 8 — owner rulings
/// 2026-10-31 / 2026-11-01): the whole Range-length span slides one hour per
/// − / +, with one slot of lookback and one of lookahead ("always 1 away")
/// until the day's end is in view.
///
/// Every expected `firstVisible` below is hand-derived from the rules
/// (clamped to `walkable.lowerBound ... walkable.upperBound − V`):
///   open:    f = first − 1                        (one earlier slot)
///   forward: f = min(f + 1, max(f, last + 2 − V))
///   back:    f = max(f − 1, min(f, first − 1))
/// and, when the span is at least as long as the window (`L ≥ V`):
///   f = first (open and every step).
/// With V = L + 2 the forward and back targets coincide at `first − 1`, so
/// mid-day the window moves exactly with the span.
final class HourCarouselTests: XCTestCase {

    // A 16-hour day (walkable 0..<16), a 4-hour Range 4..<8, V = 4 + 2 = 6.
    private func fourHour() -> HourCarousel {
        HourCarousel(walkable: 0..<16, rangeHours: 4..<8, visibleSlots: 6)
    }

    // MARK: Opening state

    func testOpensWithTheSpanOnTheRangeAndOneEarlierSlotVisible() {
        let c = fourHour()
        XCTAssertEqual(c.span, 4..<8)
        XCTAssertTrue(c.isAtRange)
        XCTAssertFalse(c.canReturnToRange)
        // f = 4 − 1 = 3 → visible 3..<9: lookback 3, the Range in slots 1–4,
        // lookahead 8.
        XCTAssertEqual(c.firstVisible, 3)
        XCTAssertEqual(c.visible, 3..<9)
    }

    func testARangeAtTheWalkStartPinsTheWindowToSlotZero() {
        // f = clamp(0 − 1) = 0 → visible 0..<6: the Range in slots 0–3, two
        // slots ahead.
        let c = HourCarousel(walkable: 0..<16, rangeHours: 0..<4, visibleSlots: 6)
        XCTAssertEqual(c.firstVisible, 0)
        XCTAssertFalse(c.canStepBack)
    }

    func testALateRangeOpensClampedToTheDaysEnd() {
        // Range 12..<16 ends the day: f = clamp(11) to ≤ 16 − 6 = 10.
        let c = HourCarousel(walkable: 0..<16, rangeHours: 12..<16, visibleSlots: 6)
        XCTAssertEqual(c.firstVisible, 10)
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

    // MARK: Lookahead window — 4-hour Range, 16-hour day, 6 slots

    func testForwardWindowSequenceForAFourHourRange() {
        // span 5..<9 → min(4, max(3, 8+2−6=4)) = 4; 6..<10 → 5; … 11..<15 →
        // 10; 12..<16 → 11 → clamp 10.
        var c = fourHour()
        var seen: [Int] = []
        while c.canStepForward { c.stepForward(); seen.append(c.firstVisible) }
        XCTAssertEqual(seen, [4, 5, 6, 7, 8, 9, 10, 10])
        XCTAssertEqual(c.visible.upperBound, 16, "the day's last hour is in view")
    }

    func testBackWindowSequenceForAFourHourRange() {
        // span 3..<7 → max(2, min(3, 2)) = 2 — ONE slot, the lookback slot
        // was already there; 2..<6 → 1; 1..<5 → 0; 0..<4 → −1 → clamp 0.
        var c = fourHour()
        var seen: [Int] = []
        while c.canStepBack { c.stepBack(); seen.append(c.firstVisible) }
        XCTAssertEqual(seen, [2, 1, 0, 0])
    }

    func testReversingKeepsOneSlotEitherSide() {
        // + + → span 6..<10, f 5. − → span 5..<9, f = max(4, min(5, 4)) = 4.
        var c = fourHour()
        c.stepForward(); c.stepForward()
        XCTAssertEqual(c.firstVisible, 5)
        XCTAssertEqual(c.span.lowerBound - c.firstVisible, 1, "one lookback slot")
        XCTAssertEqual(c.visible.upperBound - c.span.upperBound, 1, "one lookahead slot")
        c.stepBack()
        XCTAssertEqual(c.firstVisible, 4)
        XCTAssertEqual(c.span.lowerBound - c.firstVisible, 1)
        XCTAssertEqual(c.visible.upperBound - c.span.upperBound, 1)
    }

    func testTheWindowHoldsStillWhileTheLeadingEdgeHasLookahead() {
        // A 1-hour Range in 4 slots (the floor of 4 leaves an extra slot):
        // f opens at 3 (visible 3..<7, span at slot 1, two ahead).
        // + → span 5: max(3, 5+2−4=3) = 3 — still. + → span 6: 4 — moves.
        // − → span 5: min(4, 4) = 4 — still. − → span 4: 3 — moves.
        var c = HourCarousel(walkable: 0..<16, rangeHours: 4..<5, visibleSlots: 4)
        XCTAssertEqual(c.firstVisible, 3)
        c.stepForward()
        XCTAssertEqual(c.firstVisible, 3, "edge on the second-to-last slot — window still")
        c.stepForward()
        XCTAssertEqual(c.firstVisible, 4, "edge would pass it — window shifts one")
        c.stepBack()
        XCTAssertEqual(c.firstVisible, 4)
        c.stepBack()
        XCTAssertEqual(c.firstVisible, 3)
    }

    // MARK: 8-hour Range

    func testEightHourRangeWithTenSlots() {
        // V = 8 + 2 = 10; f opens clamp(3) to ≤ 16 − 10 = 6 → 3.
        // Forward: 5..<13 → 4; 5; 6; 8..<16 → 7 → clamp 6.
        var forward = HourCarousel(walkable: 0..<16, rangeHours: 4..<12, visibleSlots: 10)
        XCTAssertEqual(forward.firstVisible, 3)
        var seen: [Int] = []
        while forward.canStepForward { forward.stepForward(); seen.append(forward.firstVisible) }
        XCTAssertEqual(seen, [4, 5, 6, 6])

        // Back: 3..<11 → 2; 1; 0; 0.
        var back = HourCarousel(walkable: 0..<16, rangeHours: 4..<12, visibleSlots: 10)
        seen = []
        while back.canStepBack { back.stepBack(); seen.append(back.firstVisible) }
        XCTAssertEqual(seen, [2, 1, 0, 0])
    }

    func testAPillFloorCappedWindowTrailsByASlotRatherThanJumping() {
        // V capped at 9 = L + 1 under an 8-hour span: f opens 3 (≤ 7).
        // Forward: 5..<13 wants max(3, 12+2−9=5) = 5, limited to 3+1 = 4;
        // 6..<14 wants 6 → 5; 7..<15 → 6; 8..<16 → 7 (clamp 7).
        var forward = HourCarousel(walkable: 0..<16, rangeHours: 4..<12, visibleSlots: 9)
        XCTAssertEqual(forward.firstVisible, 3)
        var seen: [Int] = []
        while forward.canStepForward { forward.stepForward(); seen.append(forward.firstVisible) }
        XCTAssertEqual(seen, [4, 5, 6, 7])
        XCTAssertEqual(forward.visible.upperBound, 16)

        // Back: 3..<11 → 2; 1; 0; 0.
        var back = HourCarousel(walkable: 0..<16, rangeHours: 4..<12, visibleSlots: 9)
        seen = []
        while back.canStepBack { back.stepBack(); seen.append(back.firstVisible) }
        XCTAssertEqual(seen, [2, 1, 0, 0])
    }

    func testASpanLongerThanTheWindowAnchorsOnItsFirstHour() {
        // V capped at 6 under an 8-hour span: f = span start, clamped to
        // ≤ 16 − 6 = 10. Opens 4; forward 5,6,7,8; back from open 3,2,1,0.
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

    // MARK: "Always 1 away" — the window never moves more than one slot

    func testTheWindowNeverMovesMoreThanOneSlotPerPress() {
        for slots in 3...10 {
            for length in 1...9 {
                for start in stride(from: 0, through: 16 - length, by: 3) {
                    let opening = HourCarousel(walkable: 0..<16,
                                               rangeHours: start ..< start + length,
                                               visibleSlots: slots)
                    // Walk to the end, back to the start, then forward again.
                    var c = opening
                    var walk: [Bool] = Array(repeating: true, count: 16)
                    walk += Array(repeating: false, count: 16)
                    walk += Array(repeating: true, count: 16)
                    for forward in walk {
                        let before = c.firstVisible
                        if forward { c.stepForward() } else { c.stepBack() }
                        XCTAssertLessThanOrEqual(abs(c.firstVisible - before), 1,
                                                 "V \(slots), L \(length), Range at \(start)")
                        XCTAssertTrue(c.visible.contains(c.span.lowerBound) || c.span.count >= c.visibleSlots
                                      || c.visible.contains(c.span.upperBound - 1),
                                      "the span never leaves the window")
                    }
                }
            }
        }
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

    func testVisibleSlotCountIsRangePlusTwoWithAFloorOfFour() {
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 222), 6)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 2, availableWidth: 222), 4)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 1, availableWidth: 222), 4)
    }

    func testVisibleSlotCountNeverMakesAPillNarrowerThan22pt() {
        // floor((222 + 3) / (22 + 3)) = 9 pills fit.
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 7, availableWidth: 222), 9)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 8, availableWidth: 222), 9)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 12, availableWidth: 222), 9)
        // floor((120 + 3) / 25) = 4.
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 120), 4)
    }

    func testVisibleSlotCountBeforeLayoutUsesTheWantedCount() {
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 0), 6)
    }
}
