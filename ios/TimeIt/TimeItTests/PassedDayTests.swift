import XCTest
@testable import TimeIt

/// Owner ruling 05 a (2026-11-15): once today's chosen hours are over, the
/// card moves to TOMORROW. The fixture forecast starts 2026-06-19T12:00Z =
/// 4pm Dubai (UTC+4): a 6 – 10am Range is already over on day 0, a 3 – 7pm
/// Range is under way, a 10pm – 2am Range is tonight.
final class PassedDayTests: XCTestCase {

    private var deriver: TimeDeriver!
    private let start = ISO8601DateFormatter().date(from: "2026-06-19T12:00:00Z")!

    override func setUpWithError() throws {
        deriver = try XCTUnwrap(TimeDeriver(forecastStart: "2026-06-19T12:00:00Z", timezone: "Asia/Dubai"))
    }

    private func days(_ day0Score: Int?) -> [Day] {
        [Day(dayIndex: 0, rating: .perfect, startIndex: 0, endIndex: 2, duration: 2, score: day0Score),
         Day(dayIndex: 1, rating: .good, startIndex: 15, endIndex: 17, duration: 2, score: 61)]
    }

    private func at(_ hoursAfterStart: Double) -> Date {
        start.addingTimeInterval(hoursAfterStart * 3600)
    }

    // MARK: hasPassed

    func testAMorningRangeIsOverByTheAfternoonClock() {
        XCTAssertTrue(PassedDay.hasPassed(window: WindowSpec(startHour: 6, endHour: 10),
                                          days: days(80), deriver: deriver, now: at(0)),
                      "10am Dubai is long gone at 4pm, even while the cached day 0 still carries a score")
    }

    func testARangeUnderWayHasNotPassed() {
        XCTAssertFalse(PassedDay.hasPassed(window: WindowSpec(startHour: 15, endHour: 19),
                                           days: days(80), deriver: deriver, now: at(0)))
    }

    func testTheRangeEndIsTheMomentItPasses() {
        let window = WindowSpec(startHour: 15, endHour: 19) // 7pm Dubai = start + 3h
        XCTAssertFalse(PassedDay.hasPassed(window: window, days: days(80), deriver: deriver, now: at(2.99)))
        XCTAssertTrue(PassedDay.hasPassed(window: window, days: days(80), deriver: deriver, now: at(3)),
                      "end ≤ now: the last hour has ended")
    }

    func testANilDayZeroScoreIsTheServersOwnSignal() {
        XCTAssertTrue(PassedDay.hasPassed(window: WindowSpec(startHour: 15, endHour: 19),
                                          days: days(nil), deriver: deriver, now: at(0)),
                      "a windowed day 0 with zero window hours left reads as passed")
    }

    func testAWrappedRangeNeverPasses() {
        XCTAssertFalse(PassedDay.hasPassed(window: WindowSpec(startHour: 22, endHour: 2),
                                           days: days(nil), deriver: deriver, now: at(20)),
                       "tonight is always ahead of, or inside, the forecast")
    }

    func testNoWindowNeverPasses() {
        XCTAssertFalse(PassedDay.hasPassed(window: nil, days: days(nil), deriver: deriver, now: at(0)))
    }

    func testNoTomorrowMeansNoMove() {
        XCTAssertFalse(PassedDay.hasPassed(window: WindowSpec(startHour: 6, endHour: 10),
                                           days: [days(80)[0]], deriver: deriver, now: at(0)),
                       "without days[1] the card stays on today rather than showing nothing")
    }

    // MARK: the card's day + caption

    func testThePassedCardShowsTomorrowCaptionedTomorrow() {
        let shown = PassedDay.CardDay(passed: true)
        XCTAssertEqual(shown.dayIndex, 1)
        XCTAssertEqual(shown.caption, "Tomorrow")
        XCTAssertEqual(shown.dimmedDayIndex, 0, "today's dot greys")
    }

    func testTheLiveCardShowsTodayCaptionedAverage() {
        let shown = PassedDay.CardDay(passed: false)
        XCTAssertEqual(shown.dayIndex, 0)
        XCTAssertEqual(shown.caption, "Average")
        XCTAssertNil(shown.dimmedDayIndex)
    }

    // MARK: the bucket date key — the location's calendar, not the device's

    func testDateKeyIsTheLocationsCalendarDay() {
        XCTAssertEqual(deriver.dateKey(forDayIndex: 0), "2026-06-19")
        XCTAssertEqual(deriver.dateKey(forDayIndex: 1), "2026-06-20")
        let lateUTC = try! XCTUnwrap(TimeDeriver(forecastStart: "2026-06-19T21:00:00Z", timezone: "Asia/Dubai"))
        XCTAssertEqual(lateUTC.dateKey(forDayIndex: 0), "2026-06-20",
                       "21:00Z is 1am on the 20th in Dubai")
    }

    func testShortWeekdayIsTheLocationsDay() {
        XCTAssertEqual(deriver.shortWeekday(forDayIndex: 0), "Fri", "19 June 2026 is a Friday")
        XCTAssertEqual(deriver.shortWeekday(forDayIndex: 2), "Sun")
    }
}

/// "7 – 10am · Perfect" — the verdict line on the card, the Report hero, the
/// hours-over row and the Coming days list; "No good time" on a null day
/// (owner ruling 07 a).
final class VerdictLineTests: XCTestCase {

    private var deriver: TimeDeriver!

    override func setUpWithError() throws {
        // 2026-06-19T02:00Z = 6am Dubai: index 1 = 7am, index 4 = 10am.
        deriver = try XCTUnwrap(TimeDeriver(forecastStart: "2026-06-19T02:00:00Z", timezone: "Asia/Dubai"))
    }

    func testSpanLabelIsSpacedAndCollapsesTheMeridiem() {
        XCTAssertEqual(RangeText.spanLabel(startHour: 7, endHour: 10), "7 – 10am")
        XCTAssertEqual(RangeText.spanLabel(startHour: 23, endHour: 0), "11pm – 12am")
        XCTAssertEqual(RangeText.spanLabel(startHour: 15, endHour: 19), "3 – 7pm")
    }

    func testARatedDayReadsItsWindowAndVerdict() {
        let line = VerdictLine(day: Day(dayIndex: 0, rating: .perfect, startIndex: 1, endIndex: 4, duration: 3, score: 86),
                               deriver: deriver)
        XCTAssertEqual(line.text, "7 – 10am · Perfect")
        XCTAssertEqual(line.window, "7 – 10am")
        XCTAssertEqual(line.verdict, "Perfect")
        XCTAssertEqual(line.rating, .perfect)
    }

    func testAGoodDay() {
        let line = VerdictLine(day: Day(dayIndex: 0, rating: .good, startIndex: 0, endIndex: 1, duration: 1, score: 50),
                               deriver: deriver)
        XCTAssertEqual(line.text, "6 – 7am · Good")
    }

    func testANullOrUnknownDayIsNoGoodTime() {
        for rating in [nil, Rating.unknown("legendary")] {
            let line = VerdictLine(day: Day(dayIndex: 0, rating: rating, score: 31), deriver: deriver)
            XCTAssertEqual(line.text, "No good time")
            XCTAssertNil(line.rating)
            XCTAssertEqual(line.tint, Theme.badRed)
        }
        XCTAssertEqual(VerdictLine(day: nil, deriver: deriver).text, "No good time")
    }

    func testTheTintIsTheVerdictsNotTheScores() {
        let line = VerdictLine(day: Day(dayIndex: 0, rating: .perfect, startIndex: 1, endIndex: 2, duration: 1, score: 20),
                               deriver: deriver)
        XCTAssertEqual(line.tint, Theme.perfectGreen, "a 20 ring stays red; its Perfect line stays green")
    }
}
