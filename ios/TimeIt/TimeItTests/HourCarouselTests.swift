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

    // MARK: Direct V ≤ L input (visibleSlotCount never produces V < L; the clamp stays safe)

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
        // L 6, V 7 (V = L + 1, as for a 9-hour Range at 10 slots): lead 1, trail 0 →
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

    /// The hero's pill viewport: 237 column − 2·24 pieces − 2·4 gaps.
    private let viewport = 181.0

    func testVisibleSlotCountIsRangePlusTwoWithAFloorOfFour() {
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: viewport), 6)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 2, availableWidth: viewport), 4)
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 1, availableWidth: viewport), 4)
    }

    func testTheFifteenPointFloorFitsAnEightHourRangePlusTwo() {
        // floor((181 + 3) / (15 + 3)) = floor(10.22) = 10 slots fit.
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 8, availableWidth: viewport), 10)
        // (181 − 9·3) / 10 = 15.4pt pills.
        XCTAssertEqual(HourCarousel.pillWidth(slots: 10, availableWidth: viewport), 15.4, accuracy: 0.0001)
        // A wider row is still capped at the wanted Range + 2:
        // floor(225 / 18) = 12 fit, wanted 10.
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 8, availableWidth: 222), 10)
    }

    func testALongRangeShrinksItsPillsRatherThanOverflow() {
        // L 9: wanted 11, 10 fit → 10 (the lookahead slot gives way).
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 9, availableWidth: viewport), 10)
        // L 12: wanted 14, 10 fit → clamped UP to the Range length, 12:
        // (181 − 11·3) / 12 = 12.333pt pills.
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 12, availableWidth: viewport), 12)
        XCTAssertEqual(HourCarousel.pillWidth(slots: 12, availableWidth: viewport), 12.333, accuracy: 0.001)
    }

    func testTheSpanAlwaysFitsInsideTheViewport() {
        // For every Range length 1…12 in the hero viewport: the span's pills
        // plus their inner gaps never exceed the viewport width, and the
        // opening highlight's slots all lie inside the visible window.
        for length in 1...12 {
            let slots = HourCarousel.visibleSlotCount(rangeLength: length, availableWidth: viewport)
            let pill = HourCarousel.pillWidth(slots: slots, availableWidth: viewport)
            let spanWidth = Double(length) * pill + Double(length - 1) * 3
            XCTAssertLessThanOrEqual(spanWidth, viewport + 0.0001, "L \(length)")
            let c = HourCarousel(walkable: 0..<24, rangeHours: 6 ..< 6 + length, visibleSlots: slots)
            XCTAssertTrue(c.visible.contains(c.span.lowerBound), "L \(length)")
            XCTAssertTrue(c.visible.contains(c.span.upperBound - 1), "L \(length)")
        }
    }

    func testUpToEightHoursThereIsOneSpareSlotEachSide() {
        // A mid-day Range (walk 0..<24, Range from 6): the slot before and
        // the slot after the span are both visible at rest.
        for length in 1...8 {
            let slots = HourCarousel.visibleSlotCount(rangeLength: length, availableWidth: viewport)
            XCTAssertGreaterThanOrEqual(slots, length + 2, "L \(length)")
            let c = HourCarousel(walkable: 0..<24, rangeHours: 6 ..< 6 + length, visibleSlots: slots)
            XCTAssertTrue(c.visible.contains(c.span.lowerBound - 1), "lookback, L \(length)")
            XCTAssertTrue(c.visible.contains(c.span.upperBound), "lookahead, L \(length)")
        }
    }

    func testPillsNarrowerThan22ptAreCompact() {
        // 4-hour Range: (181 − 15) / 6 = 27.67 → regular numeral; 8-hour:
        // 15.4 → compact 9pt.
        XCTAssertGreaterThanOrEqual(HourCarousel.pillWidth(slots: 6, availableWidth: viewport),
                                    HourCarousel.compactPillWidth)
        XCTAssertLessThan(HourCarousel.pillWidth(slots: 10, availableWidth: viewport),
                          HourCarousel.compactPillWidth)
    }

    func testVisibleSlotCountBeforeLayoutUsesTheWantedCount() {
        XCTAssertEqual(HourCarousel.visibleSlotCount(rangeLength: 4, availableWidth: 0), 6)
    }
}
