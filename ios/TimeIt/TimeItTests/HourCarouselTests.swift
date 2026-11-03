import XCTest
@testable import TimeIt

/// The detail hero carousel as a native scroll row (depth & polish pass,
/// build 8 — owner rulings 2026-10-31 / 2026-11-01 / 2026-11-03): the whole
/// Range-length span sits under a FIXED highlight window `lead` slots in from
/// the leading edge, and derives from the row's scroll position.
///
/// Every expected value below is hand-derived from the rules
/// (W = walkable, L = span length, V = visible slots):
///   lead   = V > L ? 1 : 0
///   trail  = max(0, V − lead − L)
///   slots  = W.lower − lead ..< W.upper + trail
///   anchor = span.lower − lead
///   span(anchor).lower = clamp(anchor + lead, W.lower, W.upper − L)
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
        // lead 1 → anchor 4 − 1 = 3 → visible 3..<9: lookback 3, the Range in
        // slots 1–4, lookahead 8.
        XCTAssertEqual(c.leadSlots, 1)
        XCTAssertEqual(c.scrollAnchor, 3)
        XCTAssertEqual(c.visible, 3..<9)
    }

    func testARangeAtTheWalkStartOpensOnTheBlankLeadingPad() {
        // anchor = 0 − 1 = −1: the leading pad slot sits in the lookback
        // position (the old model pinned the window to slot 0 instead — a
        // fixed highlight cannot, so the pad shows as an empty slot).
        let c = HourCarousel(walkable: 0..<16, rangeHours: 0..<4, visibleSlots: 6)
        XCTAssertEqual(c.scrollAnchor, -1)
        XCTAssertEqual(c.slotIDs, -1..<17, "trail = 6 − 1 − 4 = 1")
        XCTAssertFalse(c.walkable.contains(c.slotIDs.lowerBound), "the pad is blank")
        XCTAssertFalse(c.canStepBack)
    }

    func testALateRangeOpensWithItsLookaheadOnTheTrailingPad() {
        // Range 12..<16 ends the day: anchor 11, visible 11..<17 — slot 16
        // is the trailing pad.
        let c = HourCarousel(walkable: 0..<16, rangeHours: 12..<16, visibleSlots: 6)
        XCTAssertEqual(c.scrollAnchor, 11)
        XCTAssertEqual(c.visible.upperBound, c.slotIDs.upperBound,
                       "the furthest snap is exactly the span-at-walk-end position")
        XCTAssertFalse(c.canStepForward)
    }

    func testNoRangeTodayGivesAOneHourSpanAtTheWalkStartAndNoReturn() {
        let c = HourCarousel(walkable: 3..<12, rangeHours: nil, visibleSlots: 4)
        XCTAssertEqual(c.span, 3..<4)
        XCTAssertFalse(c.isAtRange)
        XCTAssertFalse(c.canReturnToRange, "nothing to return to")
        XCTAssertFalse(c.overlapsRange)
        // lead 1, trail 4 − 1 − 1 = 2 → slots 2..<14, anchor 2.
        XCTAssertEqual(c.slotIDs, 2..<14)
        XCTAssertEqual(c.scrollAnchor, 2)
    }

    func testAWalkShorterThanTheViewportIsPaddedToFillIt() {
        // W 0..<3, L 2, V 5: lead 1, trail 5 − 1 − 2 = 2 → 6 slots ≥ V.
        let c = HourCarousel(walkable: 0..<3, rangeHours: 0..<2, visibleSlots: 5)
        XCTAssertEqual(c.slotIDs, -1..<5)
        XCTAssertGreaterThanOrEqual(c.slotIDs.count, c.visibleSlots)
    }

    // MARK: Span ↔ scroll position

    func testTheSpanFollowsTheScrollAnchorOneHourPerSlot() {
        let c = fourHour()
        XCTAssertEqual(c.span(forScrollAnchor: 3), 4..<8)
        XCTAssertEqual(c.span(forScrollAnchor: 4), 5..<9)
        XCTAssertEqual(c.span(forScrollAnchor: 2), 3..<7)
        XCTAssertEqual(c.span(forScrollAnchor: -1), 0..<4, "the pad anchor = the walk start")
    }

    func testAnchorsPastEitherEndClamp() {
        let c = fourHour()
        XCTAssertEqual(c.span(forScrollAnchor: -9), 0..<4)
        // The furthest real snap: slots −1..<17, V 6 → anchor 11 → 12..<16.
        XCTAssertEqual(c.span(forScrollAnchor: 11), 12..<16)
        XCTAssertEqual(c.span(forScrollAnchor: 40), 12..<16)
    }

    func testEveryReachableAnchorRoundTrips() {
        // Over many shapes, every snap position the row can rest on maps to a
        // span whose own anchor is that position — the highlight is never
        // misaligned — except the clamped tail of an over-long span.
        for slots in 1...10 {
            for length in 1...9 {
                for start in stride(from: 0, through: 16 - length, by: 3) {
                    let c = HourCarousel(walkable: 0..<16,
                                         rangeHours: start ..< start + length,
                                         visibleSlots: slots)
                    let maxAnchor = c.slotIDs.upperBound - c.visibleSlots
                    for anchor in c.slotIDs.lowerBound ... maxAnchor {
                        var moved = c
                        moved.settle(onScrollAnchor: anchor)
                        XCTAssertTrue(c.walkable.lowerBound <= moved.span.lowerBound
                                      && moved.span.upperBound <= c.walkable.upperBound)
                        XCTAssertEqual(moved.span.count, length)
                        if slots > length {
                            XCTAssertEqual(moved.scrollAnchor, anchor,
                                           "V \(slots), L \(length), Range at \(start)")
                        }
                    }
                }
            }
        }
    }

    // MARK: A long Range under the pill floor (V ≤ L)

    func testASpanWiderThanTheViewportAnchorsOnItsFirstHour() {
        // L 8, V 7: lead 0, trail max(0, 7 − 0 − 8) = 0 → slots 0..<16,
        // anchor = span start 4. Max snap anchor 16 − 7 = 9 → span clamps at
        // 8..<16 from anchor 8 on.
        var c = HourCarousel(walkable: 0..<16, rangeHours: 4..<12, visibleSlots: 7)
        XCTAssertEqual(c.leadSlots, 0)
        XCTAssertEqual(c.trailSlots, 0)
        XCTAssertEqual(c.slotIDs, 0..<16)
        XCTAssertEqual(c.scrollAnchor, 4)
        XCTAssertEqual(c.span(forScrollAnchor: 8), 8..<16)
        XCTAssertEqual(c.span(forScrollAnchor: 9), 8..<16, "clamped tail")
        c.settle(onScrollAnchor: 9)
        XCTAssertFalse(c.canStepForward)
    }

    func testOneSlotShortOfRangePlusTwoKeepsTheLookbackAndDropsTheLookahead() {
        // L 6, V 7 (a 181pt viewport floor-caps at 7): lead 1, trail 0 →
        // slots −1..<16; max anchor 16 − 7 = 9 → span 10..<16 exactly.
        let c = HourCarousel(walkable: 0..<16, rangeHours: 4..<10, visibleSlots: 7)
        XCTAssertEqual(c.leadSlots, 1)
        XCTAssertEqual(c.trailSlots, 0)
        XCTAssertEqual(c.span(forScrollAnchor: 9), 10..<16)
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
        XCTAssertEqual(c.scrollAnchor, -1, "the row rests on the leading pad")
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
        XCTAssertEqual(c.scrollAnchor, 4, "the row moves exactly with the span")
        c.stepBack()
        c.stepBack()
        XCTAssertEqual(c.span, 3..<7)
    }

    func testStepByWholeHoursClamps() {
        var c = fourHour()
        c.step(by: 3)
        XCTAssertEqual(c.span, 7..<11)
        c.step(by: -20)
        XCTAssertEqual(c.span, 0..<4, "a long move clamps at the walk start")
    }

    // MARK: Return to range

    func testReturnToRangeRestoresTheOpeningState() {
        var c = fourHour()
        let opening = c
        for _ in 0..<6 { c.stepForward() }
        XCTAssertFalse(c.isAtRange)
        XCTAssertTrue(c.canReturnToRange)
        c.returnToRange()
        XCTAssertEqual(c, opening)
        XCTAssertEqual(c.scrollAnchor, opening.scrollAnchor)
        XCTAssertFalse(c.canReturnToRange)

        c.settle(onScrollAnchor: 0)
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

    // MARK: Visible-slot count (owner-tunable)

    func testVisibleSlotCountIsRangePlusTwoWithAFloorOfFour() {
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 181), 6)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 2, availableWidth: 181), 4)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 1, availableWidth: 181), 4)
    }

    func testVisibleSlotCountNeverMakesAPillNarrowerThan22pt() {
        // The hero's 181pt viewport: floor((181 + 3) / (22 + 3)) = 7 fit.
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 5, availableWidth: 181), 7)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 6, availableWidth: 181), 7)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 12, availableWidth: 181), 7)
        // floor((222 + 3) / 25) = 9; floor((120 + 3) / 25) = 4.
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 8, availableWidth: 222), 9)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 120), 4)
    }

    func testVisibleSlotCountBeforeLayoutUsesTheWantedCount() {
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 0), 6)
    }
}
