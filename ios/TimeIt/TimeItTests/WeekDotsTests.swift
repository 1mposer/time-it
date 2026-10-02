import XCTest
@testable import TimeIt

/// The week-dot row — "the one way to show days" (owner ruling 2026-10-02,
/// Figma component `517:73`). Pure model: seven dots in FORECAST order from
/// today, a weekday initial in the forecast's zone, a tier per day.
///
/// Every expected letter below is read off a printed calendar, not the code:
/// the committed real fixture starts 2026-07-12T14:00:00Z = 18:00 Asia/Dubai
/// (UTC+4) on SUNDAY 12 July 2026 (July 2026: the 12th falls in the Su
/// column), so days 0…6 are Sun 12, Mon 13, Tue 14, Wed 15, Thu 16, Fri 17,
/// Sat 18 → S M T W T F S. Day 0 is a Sunday, not a Monday.
final class WeekDotsTests: XCTestCase {

    private var realDeriver: TimeDeriver!

    override func setUpWithError() throws {
        let response = try JSONDecoder().decode(ForecastResponse.self,
                                                from: Data(RealBackendResponse.json.utf8))
        XCTAssertEqual(response.forecastStart, "2026-07-12T14:00:00Z")
        realDeriver = try XCTUnwrap(TimeDeriver(forecastStart: response.forecastStart,
                                                timezone: response.timezone))
    }

    private func activity(_ days: [Day]) -> ActivityRating {
        ActivityRating(activityId: "a", label: "A", displayMetrics: ["temp"], days: days)
    }

    private func nullDay(_ index: Int, score: Int? = 1) -> Day {
        Day(dayIndex: index, rating: nil, score: score)
    }

    // MARK: order + letters

    func testDotsRunInForecastOrderFromTodayWithZoneLetters() {
        let dots = WeekDots.dots(for: activity((0..<7).map { nullDay($0) }), deriver: realDeriver)

        XCTAssertEqual(dots.map(\.dayIndex), [0, 1, 2, 3, 4, 5, 6], "forecast order from today, never Mon-first")
        XCTAssertEqual(dots.map(\.letter), ["S", "M", "T", "W", "T", "F", "S"],
                       "Sun 12 Jul 2026 (Dubai) is day 0")
    }

    // MARK: tiers

    func testTierMapping() {
        let days = [
            Day(dayIndex: 0, rating: .perfect, startIndex: 1, endIndex: 4, duration: 3, score: 88),
            Day(dayIndex: 1, rating: .good, startIndex: 30, endIndex: 33, duration: 3, score: 61),
            Day(dayIndex: 2, rating: nil, score: 31),                // null verdict, real score → bad
            Day(dayIndex: 3, rating: nil, score: nil),               // zero-hour bucket → no data
            Day(dayIndex: 4, rating: .unknown("great"), score: 70),  // never favourable → bad
            Day(dayIndex: 5, rating: .unknown("great"), score: nil), // unknown, no hours → no data
            Day(dayIndex: 6, rating: nil, score: 1),
        ]

        let tiers = WeekDots.dots(for: activity(days), deriver: realDeriver).map(\.tier)

        XCTAssertEqual(tiers, [.perfect, .good, .bad, .noData, .bad, .noData, .bad])
    }

    /// Precedence pin: the verdict wins over a missing score. A rated day
    /// always has hours on the wire; a nil score beside a real verdict can
    /// only come from the client decoder dropping an out-of-contract score —
    /// the verdict is still real, so the dot keeps it (ADR-0011 independence).
    func testARealVerdictWinsOverAMissingScore() {
        let days = [
            Day(dayIndex: 0, rating: .perfect, startIndex: 1, endIndex: 4, duration: 3, score: nil),
            Day(dayIndex: 1, rating: .good, startIndex: 30, endIndex: 33, duration: 3, score: nil),
        ]

        let tiers = WeekDots.dots(for: activity(days), deriver: realDeriver).prefix(2).map(\.tier)

        XCTAssertEqual(tiers, [.perfect, .good])
    }

    // MARK: always seven

    func testNocturnalSixBucketsGetANoDataSeventhDot() {
        let dots = WeekDots.dots(for: activity((0..<6).map { nullDay($0) }), deriver: realDeriver)

        XCTAssertEqual(dots.count, 7, "exactly seven dots, even for a 6-night activity")
        XCTAssertEqual(dots[6].dayIndex, 6)
        XCTAssertEqual(dots[6].letter, "S", "day 6 = Sat 18 Jul")
        XCTAssertEqual(dots[6].tier, .noData, "the absent tail day is no data")
    }

    func testEightDayDiurnalDropsTheEighthDay() {
        let days = (0..<8).map { index -> Day in
            index == 7 ? Day(dayIndex: 7, rating: .perfect, startIndex: 150, endIndex: 156, duration: 6, score: 90)
                       : nullDay(index)
        }

        let dots = WeekDots.dots(for: activity(days), deriver: realDeriver)

        XCTAssertEqual(dots.count, 7)
        XCTAssertEqual(dots.map(\.dayIndex), Array(0...6))
        XCTAssertFalse(dots.contains { $0.tier == .perfect }, "the 8th (Perfect) day never reaches the row")
    }

    /// Reads the real 8-bucket cycling activity end to end: days 0/3/6 are
    /// rating-null — this pre-ADR-0011 capture carries no `score`, so they
    /// are no-data; days 1/2/4/5 are Perfect (the verdict wins); day 7 drops.
    func testRealFixtureCyclingRow() throws {
        let response = try JSONDecoder().decode(ForecastResponse.self,
                                                from: Data(RealBackendResponse.json.utf8))
        let cycling = try XCTUnwrap(response.activities.first { $0.activityId == "cycling" })

        let tiers = WeekDots.dots(for: cycling, deriver: realDeriver).map(\.tier)

        XCTAssertEqual(tiers, [.noData, .perfect, .perfect, .noData, .perfect, .perfect, .noData])
    }

    // MARK: accessibility names

    func testDotNamesReadTodayTomorrowThenWeekdays() {
        let dots = WeekDots.dots(for: activity((0..<7).map { nullDay($0) }), deriver: realDeriver)

        XCTAssertEqual(dots.map(\.name),
                       ["Today", "Tomorrow", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"])
    }

    /// A night activity keys dayIndex to the evening (ADR-0004 amendment), so
    /// its dots are named by the night: day 0 "Tonight", day 1 "Tomorrow
    /// night", day 2 = Tue 14 Jul → "Tuesday night". Letters stay the
    /// evening's weekday initial. Diurnal (the default) stays "Today".
    func testNocturnalDotsAreNamedByTheNight() {
        let days = [Day(dayIndex: 0, rating: .perfect, startIndex: 4, endIndex: 8, duration: 4, score: 80)]
            + (1..<6).map { nullDay($0) }

        let night = WeekDots.dots(for: activity(days), deriver: realDeriver, nocturnal: true)
        let diurnal = WeekDots.dots(for: activity(days), deriver: realDeriver)

        XCTAssertEqual(night[0].name, "Tonight")
        XCTAssertEqual(night[1].name, "Tomorrow night")
        XCTAssertEqual(night[2].name, "Tuesday night")
        XCTAssertEqual(night[0].accessibilityLabel, "Tonight, Perfect")
        XCTAssertEqual(night[1].accessibilityLabel, "Tomorrow night, No window")
        XCTAssertEqual(night[0].letter, "S", "the evening's weekday — Sun 12 Jul")
        XCTAssertEqual(diurnal[0].name, "Today")
        XCTAssertEqual(diurnal[1].name, "Tomorrow")
    }

    func testAccessibilityLabelSpellsTheVerdict() {
        XCTAssertEqual(WeekDot(dayIndex: 0, letter: "S", name: "Today", tier: .perfect).accessibilityLabel,
                       "Today, Perfect")
        XCTAssertEqual(WeekDot(dayIndex: 1, letter: "M", name: "Tomorrow", tier: .good).accessibilityLabel,
                       "Tomorrow, Good")
        XCTAssertEqual(WeekDot(dayIndex: 2, letter: "T", name: "Tuesday", tier: .bad).accessibilityLabel,
                       "Tuesday, No window")
        XCTAssertEqual(WeekDot(dayIndex: 3, letter: "W", name: "Wednesday", tier: .noData).accessibilityLabel,
                       "Wednesday, No data")
    }

    func testOnlyDataDotsAreJumpable() {
        XCTAssertTrue(WeekDot(dayIndex: 0, letter: "S", name: "Today", tier: .bad).isJumpable)
        XCTAssertFalse(WeekDot(dayIndex: 6, letter: "S", name: "Saturday", tier: .noData).isJumpable)
    }
}
