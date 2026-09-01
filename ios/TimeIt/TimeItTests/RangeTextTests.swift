import XCTest
@testable import TimeIt

/// Rendering copy derived from the authored Range (pure hour ints — no
/// timezone math): the card's range chip ("6 – 10am"), the detail header
/// ("10pm – 4am nightly" — prefix-less, owner prune 2026-09-01), and the
/// detail week's range-zoomed axis (start / midpoint / end).
final class RangeTextTests: XCTestCase {

    // MARK: hourText (one clock dialect)

    func testHourTextMatchesTheAxisLabelStyle() {
        XCTAssertEqual(RangeText.hourText(0), "12am")
        XCTAssertEqual(RangeText.hourText(6), "6am")
        XCTAssertEqual(RangeText.hourText(12), "12pm")
        XCTAssertEqual(RangeText.hourText(15), "3pm")
        XCTAssertEqual(RangeText.hourText(23), "11pm")
    }

    // MARK: range chip — "6 – 10am" (same-meridiem collapse, spaced dash)

    func testChipLabelCollapsesSameMeridiem() {
        XCTAssertEqual(RangeText.chipLabel(WindowSpec(startHour: 6, endHour: 10)), "6 – 10am")
        XCTAssertEqual(RangeText.chipLabel(WindowSpec(startHour: 15, endHour: 19)), "3 – 7pm")
    }

    func testChipLabelKeepsBothSuffixesAcrossMeridiem() {
        XCTAssertEqual(RangeText.chipLabel(WindowSpec(startHour: 22, endHour: 4)), "10pm – 4am")
        XCTAssertEqual(RangeText.chipLabel(WindowSpec(startHour: 8, endHour: 12)), "8am – 12pm")
    }

    // MARK: detail window header — range stated once

    func testHeaderLabelSaysDailyForDiurnal() {
        XCTAssertEqual(RangeText.headerLabel(WindowSpec(startHour: 6, endHour: 10)),
                       "6 – 10am daily")
    }

    func testHeaderLabelSaysNightlyForNocturnal() {
        XCTAssertEqual(RangeText.headerLabel(WindowSpec(startHour: 22, endHour: 4)),
                       "10pm – 4am nightly")
    }

    // MARK: range-zoomed axis — start / midpoint / end, once under the stack

    func testAxisLabelsForDiurnalRange() {
        XCTAssertEqual(RangeText.axisLabels(WindowSpec(startHour: 6, endHour: 10)),
                       ["6am", "8am", "10am"])
    }

    func testAxisLabelsForNocturnalRangeCrossMidnight() {
        XCTAssertEqual(RangeText.axisLabels(WindowSpec(startHour: 22, endHour: 4)),
                       ["10pm", "1am", "4am"])
    }

    func testAxisMidpointFloorsOnOddDurations() {
        // 6–9am is 3 hours; the midpoint hour floors to 7am (whole-hour Ranges).
        XCTAssertEqual(RangeText.axisLabels(WindowSpec(startHour: 6, endHour: 9)),
                       ["6am", "7am", "9am"])
    }
}
