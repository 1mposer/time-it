import XCTest
@testable import TimeIt

/// The detail week bar's pure layer (§7.3, audit follow-up 2026-08-17): where
/// a day's COVERED range hours sit on the shared range-zoomed axis, and what
/// the bar paints. The rule the audit pinned: red is reserved for
/// BAD-WITH-DATA — a Range the forecast doesn't cover paints the plain track,
/// and a partially-covered rated day paints only its true sub-span (stretching
/// fewer tiers across the full width would fabricate verdicts for hours that
/// have no data).
final class RangeAxisTests: XCTestCase {

    private let morning = WindowSpec(startHour: 6, endHour: 10)     // 4 slots
    private let nocturnal = WindowSpec(startHour: 22, endHour: 4)   // 6 slots

    // MARK: slot count

    func testSlotCountIsTheRangeDuration() {
        XCTAssertEqual(RangeAxis.slotCount(morning), 4)
        XCTAssertEqual(RangeAxis.slotCount(WindowSpec(startHour: 15, endHour: 19)), 4)
    }

    func testSlotCountWrapsMidnight() {
        XCTAssertEqual(RangeAxis.slotCount(nocturnal), 6)
        XCTAssertEqual(RangeAxis.slotCount(WindowSpec(startHour: 23, endHour: 1)), 2)
    }

    // MARK: coverage span

    func testFullCoverageSpansTheWholeAxis() {
        XCTAssertEqual(RangeAxis.coverageSpan(window: morning, localHours: [6, 7, 8, 9]), 0..<1)
    }

    func testLeadingGapStartsTheSpanAtItsTrueClockPosition() {
        // Forecast opens mid-range (a 6–10am activity viewed at 8am): hours
        // 6–7 are gone — the covered half paints at the RIGHT half of the
        // axis, not stretched from the left edge.
        XCTAssertEqual(RangeAxis.coverageSpan(window: morning, localHours: [8, 9]), 0.5..<1)
    }

    func testTrailingGapEndsTheSpanEarly() {
        // Horizon ends mid-range (the partial tail bucket): only 6–8am exists.
        XCTAssertEqual(RangeAxis.coverageSpan(window: morning, localHours: [6, 7]), 0..<0.5)
    }

    func testSingleCoveredHourOccupiesItsOwnSlot() {
        XCTAssertEqual(RangeAxis.coverageSpan(window: morning, localHours: [7]), 0.25..<0.5)
    }

    func testNocturnalFullNightSpansTheWholeAxis() {
        XCTAssertEqual(RangeAxis.coverageSpan(window: nocturnal,
                                              localHours: [22, 23, 0, 1, 2, 3]), 0..<1)
    }

    func testNocturnalTailNightCoversTheEveningOnly() throws {
        // The horizon's last evening has no morning after it — its two
        // evening hours sit at the START of the night axis.
        let span = try XCTUnwrap(RangeAxis.coverageSpan(window: nocturnal, localHours: [22, 23]))
        XCTAssertEqual(span.lowerBound, 0, accuracy: 1e-9)
        XCTAssertEqual(span.upperBound, 1.0 / 3, accuracy: 1e-9)
    }

    func testNocturnalMorningTailSitsAtTheEndOfTheNightAxis() {
        // Forecast opens at 1am: tonight's bucket has only the morning tail —
        // slots (h − 22 + 24) % 24 = 3, 4, 5 of 6.
        XCTAssertEqual(RangeAxis.coverageSpan(window: nocturnal, localHours: [1, 2, 3]), 0.5..<1)
    }

    func testNoCoveredHoursMeansNoSpan() {
        XCTAssertNil(RangeAxis.coverageSpan(window: morning, localHours: []))
    }

    func testAnHourOutsideTheRangeInvalidatesTheSpan() {
        // Defensive: the callers only pass range hours; a stray out-of-range
        // hour means the inputs disagree — paint nothing rather than lie.
        XCTAssertNil(RangeAxis.coverageSpan(window: morning, localHours: [6, 7, 12]))
    }

    // MARK: the paint decision (the audit's three cases + the rated fallback)

    func testNilRatingWithNoCoverageIsThePlainTrack() {
        // Case 1: range fully outside the forecast — red is reserved for
        // bad-with-data (the same rule the card already follows).
        XCTAssertEqual(DayBarPaint.decide(rating: nil, tiers: [], coverage: nil), .track)
    }

    func testNilRatingWithCoverageIsSolidRed() {
        // Case 2 — unchanged: the server judged the covered hours and found
        // nothing; bad weather is painted, never absent.
        XCTAssertEqual(DayBarPaint.decide(rating: nil, tiers: [.red], coverage: 0..<1), .solidRed)
    }

    func testRatedDayWithCoveragePaintsTheGradientOverItsSpan() {
        // Case 3: the sub-span rides through so a partially-covered rated day
        // paints at its true clock position.
        XCTAssertEqual(DayBarPaint.decide(rating: "perfect", tiers: [.green, .orange], coverage: 0.5..<1),
                       .slice(span: 0.5..<1, tiers: [.green, .orange]))
    }

    func testRatedDayWithoutMirrorDataFallsBackToTheFlatServerVerdict() {
        // Authored-lookup miss: no tiers to blend — the flat server rating
        // fill (pre-existing fallback, unchanged).
        XCTAssertEqual(DayBarPaint.decide(rating: "good", tiers: [], coverage: nil), .flat)
        XCTAssertEqual(DayBarPaint.decide(rating: "good", tiers: [.green], coverage: nil), .flat)
        XCTAssertEqual(DayBarPaint.decide(rating: "good", tiers: [], coverage: 0..<1), .flat)
    }
}
