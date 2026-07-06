import XCTest
@testable import TimeIt

/// forecastStart 2026-06-19T12:00:00Z in Asia/Dubai (UTC+4) = Friday 19 June, 16:00 local.
/// Mirrors the ADR-0003 worked example: 164 hours → 8 local-day buckets of 8 / 24×6 / 12.
final class TimeDerivationTests: XCTestCase {

    private var deriver: TimeDeriver!

    override func setUpWithError() throws {
        deriver = try XCTUnwrap(TimeDeriver(forecastStart: "2026-06-19T12:00:00Z", timezone: "Asia/Dubai"))
    }

    func testHourLabelIsInResponseZone() {
        XCTAssertEqual(deriver.hourLabel(at: 0), "4pm")   // 12:00 UTC = 16:00 Dubai
        XCTAssertEqual(deriver.hourLabel(at: 7), "11pm")
        XCTAssertEqual(deriver.hourLabel(at: 8), "12am")  // crosses local midnight
        XCTAssertEqual(deriver.hourLabel(at: 20), "12pm")
    }

    func testDayNames() {
        XCTAssertEqual(deriver.dayName(forDayIndex: 0), "Today")
        XCTAssertEqual(deriver.dayName(forDayIndex: 1), "Tomorrow")
        XCTAssertEqual(deriver.dayName(forDayIndex: 2), "Sunday")  // 21 June 2026
        XCTAssertEqual(deriver.dayName(forDayIndex: 3), "Monday")
    }

    func testHourRangesMatchLocalDayBuckets() {
        // ADR-0003 worked example: partial day 0 (8h), six full days, partial tail (12h).
        XCTAssertEqual(deriver.hourRange(forDayIndex: 0, hourCount: 164), 0..<8)
        XCTAssertEqual(deriver.hourRange(forDayIndex: 1, hourCount: 164), 8..<32)
        XCTAssertEqual(deriver.hourRange(forDayIndex: 6, hourCount: 164), 128..<152)
        XCTAssertEqual(deriver.hourRange(forDayIndex: 7, hourCount: 164), 152..<164)
        XCTAssertNil(deriver.hourRange(forDayIndex: 8, hourCount: 164))
    }

    func testInvalidInputsReturnNil() {
        XCTAssertNil(TimeDeriver(forecastStart: "not-a-date", timezone: "Asia/Dubai"))
        XCTAssertNil(TimeDeriver(forecastStart: "2026-06-19T12:00:00Z", timezone: "Not/AZone"))
    }

    /// Guard against device-zone leakage: results must be identical under a different host zone.
    func testDerivationIsIndependentOfDeviceTimeZone() {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!

        let shifted = TimeDeriver(forecastStart: "2026-06-19T12:00:00Z", timezone: "Asia/Dubai")!
        XCTAssertEqual(shifted.hourLabel(at: 0), "4pm")
        XCTAssertEqual(shifted.dayName(forDayIndex: 2), "Sunday")
        XCTAssertEqual(shifted.hourRange(forDayIndex: 0, hourCount: 164), 0..<8)
    }
}
