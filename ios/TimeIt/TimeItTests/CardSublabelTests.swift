import XCTest
@testable import TimeIt

/// Spec 14 §2: the card sublabel gains the best-stretch time — "Today · 6–8pm"
/// — matching the push copy word-for-word (server `src/jobs/labels.js`
/// rangeLabel: same meridiem → suffix once, "7–10am"; crossing → both,
/// "10pm–2am") so a tapped push lands on its own receipt. A red day (no
/// stretch) is the plain day name.
final class CardSublabelTests: XCTestCase {

    // forecastStart 2026-06-19T12:00:00Z in Asia/Dubai (+04) → hours[0] is
    // 4pm local; index 8 is midnight, index 20 is noon the next day.
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
        // 10pm → 2am, the spec's own nocturnal example.
        XCTAssertEqual(deriver.rangeLabel(startIndex: 6, endIndex: 10), "10pm–2am")
    }

    func testNoonRendersAs12pm() {
        // 8am–12pm: "12pm" is pm, so the meridiems differ and both render.
        XCTAssertEqual(deriver.rangeLabel(startIndex: 16, endIndex: 20), "8am–12pm")
    }

    func testMidnightRendersAs12am() {
        XCTAssertEqual(deriver.rangeLabel(startIndex: 6, endIndex: 8), "10pm–12am")
        // Same-meridiem collapse strips the suffix from the start label even
        // when it is "12am" — matching the server's slice(0, -2) exactly.
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
        // rating null ⇒ no stretch: "Today"/"Tonight" with no time (spec §2 —
        // there IS no window; the solid red slice carries the verdict).
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
