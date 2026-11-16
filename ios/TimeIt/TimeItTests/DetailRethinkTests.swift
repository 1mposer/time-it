import XCTest
@testable import TimeIt

/// The tomorrow detail's Coming days list (owner ruling 2026-11-15): the days
/// AFTER the shown one — dot · day · "7 – 10am · Perfect" / "No good time"
/// (red) · "Average N" right-aligned.
final class ComingDaysTests: XCTestCase {

    private var deriver: TimeDeriver!

    override func setUpWithError() throws {
        // 2026-06-19T02:00Z = 6am Dubai, Friday 19 June.
        deriver = try XCTUnwrap(TimeDeriver(forecastStart: "2026-06-19T02:00:00Z", timezone: "Asia/Dubai"))
    }

    private func activity() -> ActivityRating {
        ActivityRating(activityId: "a", label: "A", displayMetrics: ["temp"], days: [
            Day(dayIndex: 0, rating: .perfect, startIndex: 1, endIndex: 4, duration: 3, score: 86),
            Day(dayIndex: 1, rating: .perfect, startIndex: 24, endIndex: 27, duration: 3, score: 91),
            Day(dayIndex: 2, rating: .good, startIndex: 51, endIndex: 52, duration: 1, score: 48),
            Day(dayIndex: 3, rating: nil, score: 22),
            Day(dayIndex: 4, rating: .unknown("legendary"), score: 40),
            Day(dayIndex: 5, rating: nil, score: nil),
        ])
    }

    func testRowsAreTheDaysAfterTheShownOne() {
        let rows = ComingDays.rows(for: activity(), after: 1, deriver: deriver)
        XCTAssertEqual(rows.map(\.dayIndex), [2, 3, 4, 5])
        XCTAssertEqual(rows.map(\.dayName), ["Sun", "Mon", "Tue", "Wed"])
    }

    func testARatedRowReadsItsWindowVerdictAndAverage() {
        let row = ComingDays.rows(for: activity(), after: 1, deriver: deriver)[0]
        XCTAssertEqual(row.line.text, "9 – 10am · Good", "index 51 = 9am Sunday (day 2)")
        XCTAssertEqual(row.average, "Average 48")
        XCTAssertEqual(row.tier, .good)
    }

    func testANullOrUnknownRowIsNoGoodTimeInRed() {
        let rows = ComingDays.rows(for: activity(), after: 1, deriver: deriver)
        XCTAssertEqual(rows[1].line.text, "No good time")
        XCTAssertEqual(rows[1].line.tint, Theme.badRed)
        XCTAssertEqual(rows[1].average, "Average 22")
        XCTAssertEqual(rows[2].line.text, "No good time", "an unknown verdict is never favourable")
    }

    func testANoDataRowHasNoAverage() {
        let row = ComingDays.rows(for: activity(), after: 1, deriver: deriver)[3]
        XCTAssertNil(row.average)
        XCTAssertEqual(row.tier, .noData)
    }

    func testTheListStopsAtTheWeekDotsHorizon() {
        let days = (0..<8).map { Day(dayIndex: $0, rating: nil, score: 10) }
        let rows = ComingDays.rows(for: ActivityRating(activityId: "a", label: "A", displayMetrics: [], days: days),
                                   after: 1, deriver: deriver)
        XCTAssertEqual(rows.map(\.dayIndex), [2, 3, 4, 5, 6], "seven dots, so day 7 never lists")
    }
}

/// Explore's rows (owner ruling 2026-11-15): Your hours (range · Average N) /
/// Best hours (window · verdict) / Looking at (span · Average N, only when the
/// span differs). The highlighted row is what the ring and the cards describe.
final class ExploreRowsTests: XCTestCase {

    private let best = VerdictLine(window: "7 – 10am", rating: .perfect)

    func testAtTheRangeYourHoursIsHighlighted() {
        let rows = ExploreRows.rows(range: "6 – 10am", dayScore: 86, best: best, lookingAt: nil)
        XCTAssertEqual(rows.map(\.kind), [.yourHours, .bestHours])
        XCTAssertEqual(rows[0].label, "Your hours")
        XCTAssertEqual(rows[0].value, "6 – 10am")
        XCTAssertEqual(rows[0].result, "Average 86")
        XCTAssertTrue(rows[0].isHighlighted)
        XCTAssertEqual(rows[1].label, "Best hours")
        XCTAssertEqual(rows[1].value, "7 – 10am")
        XCTAssertEqual(rows[1].result, "Perfect")
        XCTAssertEqual(rows[1].resultRating, .perfect)
        XCTAssertFalse(rows[1].isHighlighted)
    }

    func testAwayFromTheRangeLookingAtJoinsAndTakesTheHighlight() {
        let rows = ExploreRows.rows(range: "6 – 10am", dayScore: 86, best: best,
                                    lookingAt: .init(span: "7 – 11am", score: 79))
        XCTAssertEqual(rows.map(\.kind), [.yourHours, .bestHours, .lookingAt])
        XCTAssertEqual(rows[2].label, "Looking at")
        XCTAssertEqual(rows[2].value, "7 – 11am")
        XCTAssertEqual(rows[2].result, "Average 79")
        XCTAssertEqual(rows.map(\.isHighlighted), [false, false, true])
    }

    func testAnUnscoredSpanReadsADash() {
        let rows = ExploreRows.rows(range: "6 – 10am", dayScore: nil, best: best,
                                    lookingAt: .init(span: "7 – 11am", score: nil))
        XCTAssertEqual(rows[0].result, "Average \u{2014}")
        XCTAssertEqual(rows[2].result, "Average \u{2014}")
    }

    func testANullDaysBestHoursIsNoGoodTime() {
        let rows = ExploreRows.rows(range: "6 – 10am", dayScore: 31,
                                    best: VerdictLine(window: nil, rating: nil), lookingAt: nil)
        XCTAssertEqual(rows[1].value, "\u{2014}")
        XCTAssertEqual(rows[1].result, "No good time")
        XCTAssertNil(rows[1].resultRating)
    }

    func testBackLabelNamesTheRange() {
        XCTAssertEqual(ExploreRows.backLabel(range: "6 – 10am"), "Back to 6 – 10am")
    }
}

/// The Report / Explore switch is remembered per Activity, default Report,
/// and a deleted Activity's choice goes with it.
@MainActor
final class HeroModePersistenceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HeroModePersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultIsReport() {
        XCTAssertEqual(PreferencesStore(defaults: defaults).heroMode(for: "cycling"), .report)
    }

    func testTheChoiceIsRememberedPerActivity() {
        let prefs = PreferencesStore(defaults: defaults)
        prefs.setHeroMode(.explore, for: "cycling")
        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.heroMode(for: "cycling"), .explore)
        XCTAssertEqual(reloaded.heroMode(for: "running"), .report)
        reloaded.setHeroMode(.report, for: "cycling")
        XCTAssertEqual(PreferencesStore(defaults: defaults).heroMode(for: "cycling"), .report)
    }

    func testADeletedActivitysChoiceIsPruned() {
        let prefs = PreferencesStore(defaults: defaults)
        prefs.setHeroMode(.explore, for: "cycling")
        prefs.setHeroMode(.explore, for: "running")
        prefs.pruneCollapsedCards(keeping: ["running"])
        XCTAssertEqual(prefs.heroMode(for: "cycling"), .report)
        XCTAssertEqual(prefs.heroMode(for: "running"), .explore)
    }
}
