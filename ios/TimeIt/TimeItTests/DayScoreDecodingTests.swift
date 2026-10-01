import XCTest
@testable import TimeIt

/// `days[].score` (ADR-0011) is ADDITIVE and OPTIONAL. The hardening posture
/// of 2026-07-12 applies in full: absent, null, or any non-integer decodes to
/// nil, and NOTHING about this field may ever fail a decode — including at the
/// whole-response level, where a single throw would blank the dashboard.
final class DayScoreDecodingTests: XCTestCase {

    private func decodeDay(_ json: String) throws -> Day {
        try JSONDecoder().decode(Day.self, from: Data(json.utf8))
    }

    // MARK: the Day object

    func testScorePresentDecodes() throws {
        let day = try decodeDay(#"{ "dayIndex": 0, "rating": "perfect", "startIndex": 3, "endIndex": 9, "duration": 6, "score": 86 }"#)
        XCTAssertEqual(day.score, 86)
    }

    func testScoreAbsentIsNil() throws {
        // The pre-ADR-0011 server shape — an older backend must still decode.
        let day = try decodeDay(#"{ "dayIndex": 0, "rating": "perfect", "startIndex": 3, "endIndex": 9, "duration": 6 }"#)
        XCTAssertNil(day.score)
    }

    func testScoreNullIsNil() throws {
        // The documented null rule: a bucket with zero window hours.
        let day = try decodeDay(#"{ "dayIndex": 1, "rating": null, "score": null }"#)
        XCTAssertNil(day.score)
    }

    func testScoreWrongTypeIsNilAndNeverThrows() throws {
        for value in ["\"86\"", "86.5", "true", "[86]", "{}"] {
            let day = try decodeDay(#"{ "dayIndex": 0, "rating": null, "score": \#(value) }"#)
            XCTAssertNil(day.score, "score \(value) must decode to nil")
            XCTAssertEqual(day.dayIndex, 0, "the rest of the day must survive a bad score")
        }
    }

    func testScoreOutsideTheContractRangeIsNil() throws {
        // The wire contract is 1...100 (ADR-0011 clamps). An integer outside
        // it is contract-violating, so it renders as the SAFE state (an empty
        // ring) rather than painting a raw 0 or 999 — the `.unknown`
        // precedent of 2026-08-29.
        for value in [-5, 0, 101, 999] {
            let day = try decodeDay(#"{ "dayIndex": 0, "rating": "perfect", "score": \#(value) }"#)
            XCTAssertNil(day.score, "score \(value) is outside 1...100")
            XCTAssertEqual(day.rating, .perfect, "the rest of the day survives")
        }
    }

    func testTheContractBoundsThemselvesDecode() throws {
        XCTAssertEqual(try decodeDay(#"{ "dayIndex": 0, "rating": null, "score": 1 }"#).score, 1,
                       "1 is the clamped floor an all-zero day renders")
        XCTAssertEqual(try decodeDay(#"{ "dayIndex": 0, "rating": "perfect", "score": 100 }"#).score, 100)
    }

    func testARatingNullDayStillCarriesItsScore() throws {
        // Score and rating are computed independently (ADR-0011) — the card's
        // null state draws a real low score, so never gate reading it on the
        // verdict.
        let day = try decodeDay(#"{ "dayIndex": 0, "rating": null, "score": 31 }"#)
        XCTAssertNil(day.rating)
        XCTAssertFalse(day.hasWindow)
        XCTAssertEqual(day.score, 31)
    }

    func testTheExistingRatingHardeningIsUntouched() throws {
        let day = try decodeDay(#"{ "dayIndex": 0, "rating": "legendary", "score": 99 }"#)
        XCTAssertEqual(day.rating, .unknown("legendary"))
        XCTAssertFalse(day.hasWindow, "an unknown verdict is never favourable")
        XCTAssertEqual(day.score, 99)
    }

    // MARK: the whole response — one bad score must not blank the dashboard

    func testAGarbageScoreNeverFailsTheWholeResponseDecode() throws {
        let json = """
        {
          "forecastStart": "2026-06-19T12:00:00Z",
          "timezone": "Asia/Dubai",
          "activities": [
            {
              "activityId": "cycling",
              "label": "Cycling",
              "displayMetrics": ["temp", "windSpeed"],
              "days": [
                { "dayIndex": 0, "rating": "perfect", "startIndex": 3, "endIndex": 9, "duration": 6, "score": "high" },
                { "dayIndex": 1, "rating": null, "score": null },
                { "dayIndex": 2, "rating": "good", "startIndex": 52, "endIndex": 55, "duration": 3, "score": 61.5 },
                { "dayIndex": 3, "rating": null }
              ]
            }
          ],
          "hours": [\(Fixtures.hourJSON(index: 0))]
        }
        """
        let forecast = try JSONDecoder().decode(ForecastResponse.self, from: Data(json.utf8))
        let days = forecast.activities[0].days

        XCTAssertEqual(days.count, 4)
        XCTAssertNil(days[0].score, "a string score degrades to nil…")
        XCTAssertEqual(days[0].startIndex, 3, "…without costing the rest of the day")
        XCTAssertEqual(days[0].rating, .perfect)
        XCTAssertNil(days[1].score)
        XCTAssertNil(days[2].score, "a fractional score is not an integer")
        XCTAssertEqual(days[2].duration, 3)
        XCTAssertNil(days[3].score)
        XCTAssertEqual(forecast.timezone, "Asia/Dubai")
        XCTAssertEqual(forecast.hours.count, 1)
    }

    func testAValidScoreSurvivesTheWholeResponseDecode() throws {
        let json = """
        {
          "forecastStart": "2026-06-19T12:00:00Z",
          "timezone": "Asia/Dubai",
          "activities": [
            {
              "activityId": "cycling",
              "label": "Cycling",
              "displayMetrics": ["temp"],
              "days": [{ "dayIndex": 0, "rating": "perfect", "startIndex": 3, "endIndex": 9, "duration": 6, "score": 86 }]
            }
          ],
          "hours": [\(Fixtures.hourJSON(index: 0))]
        }
        """
        let forecast = try JSONDecoder().decode(ForecastResponse.self, from: Data(json.utf8))
        XCTAssertEqual(forecast.activities[0].days[0].score, 86)
    }

    /// The whole existing fixture carries no `score` at all — the decode must
    /// stay green, proving the field is genuinely additive.
    func testTheScorelessFixtureStillDecodes() throws {
        let forecast = try Fixtures.decodeForecast()
        XCTAssertEqual(forecast.activities.count, 2)
        XCTAssertTrue(forecast.activities[0].days.allSatisfy { $0.score == nil })
    }
}
