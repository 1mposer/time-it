import XCTest
@testable import TimeIt

/// The card sublabel's best-stretch time ("Today · 6–8pm") must match the
/// server's push copy word-for-word; a red day is the plain day name.
final class CardSublabelTests: XCTestCase {

    // Fixture: 2026-06-19T12:00:00Z in Asia/Dubai (+04) → hours[0] = 4pm local, index 8 = midnight, index 20 = next-day noon.
    private var deriver: TimeDeriver!

    override func setUpWithError() throws {
        deriver = try XCTUnwrap(TimeDeriver(forecastStart: "2026-06-19T12:00:00Z",
                                            timezone: "Asia/Dubai"))
    }

    // MARK: rangeLabel — the labels.js twin (endIndex is exclusive = the end boundary's clock time)

    func testSameMeridiemCollapsesTheSuffix() {
        XCTAssertEqual(deriver.rangeLabel(startIndex: 0, endIndex: 3), "4–7pm")
    }

    func testCrossingMeridiemKeepsBothSuffixes() {
        XCTAssertEqual(deriver.rangeLabel(startIndex: 6, endIndex: 10), "10pm–2am")
    }

    func testNoonRendersAs12pm() {
        XCTAssertEqual(deriver.rangeLabel(startIndex: 16, endIndex: 20), "8am–12pm")
    }

    func testMidnightRendersAs12am() {
        XCTAssertEqual(deriver.rangeLabel(startIndex: 6, endIndex: 8), "10pm–12am")
        // Same-meridiem collapse strips the start suffix even when it is "12am".
        XCTAssertEqual(deriver.rangeLabel(startIndex: 8, endIndex: 9), "12–1am")
    }

    // MARK: sublabel — day name · best stretch

    func testDiurnalSublabelJoinsDayAndStretch() {
        XCTAssertEqual(deriver.sublabel(forDayIndex: 0, startIndex: 2, endIndex: 6, nocturnal: false),
                       "Today · 6–10pm")
        XCTAssertEqual(deriver.sublabel(forDayIndex: 1, startIndex: 16, endIndex: 20, nocturnal: false),
                       "Tomorrow · 8am–12pm")
    }

    func testNocturnalSublabelSaysTonight() {
        XCTAssertEqual(deriver.sublabel(forDayIndex: 0, startIndex: 6, endIndex: 10, nocturnal: true),
                       "Tonight · 10pm–2am")
    }

    func testRedDaySublabelIsThePlainDayName() {
        XCTAssertEqual(deriver.sublabel(forDayIndex: 0, startIndex: nil, endIndex: nil, nocturnal: false),
                       "Today")
        XCTAssertEqual(deriver.sublabel(forDayIndex: 0, startIndex: nil, endIndex: nil, nocturnal: true),
                       "Tonight")
    }

    func testWeekdaySublabelForLaterDays() {
        // Day 3 from Friday 2026-06-19 (day 0) is Monday.
        XCTAssertEqual(deriver.sublabel(forDayIndex: 3, startIndex: nil, endIndex: nil, nocturnal: false),
                       "Monday")
    }
}
