import XCTest
@testable import TimeIt

final class ForecastResponseTests: XCTestCase {

    func testDecodesTopLevelFields() throws {
        let forecast = try Fixtures.decodeForecast()
        XCTAssertEqual(forecast.timezone, "Asia/Dubai")
        XCTAssertEqual(forecast.forecastStart, "2026-06-19T12:00:00Z")
        XCTAssertEqual(forecast.activities.count, 2)
        XCTAssertEqual(forecast.hours.count, 60, "hours count is provider-determined — read it from the payload")
    }

    func testForecastStartDecodesWithDefaultISO8601Formatter() throws {
        let forecast = try Fixtures.decodeForecast()
        XCTAssertNotNil(ISO8601DateFormatter().date(from: forecast.forecastStart),
                        "forecastStart must carry the Z suffix so the default formatter parses it")
    }

    func testActivitiesPreserveRequestOrder() throws {
        let forecast = try Fixtures.decodeForecast()
        XCTAssertEqual(forecast.activities.map(\.activityId), ["cycling", "fishing-lite"])
    }

    func testPerActivityDaysLengthVaries() throws {
        let forecast = try Fixtures.decodeForecast()
        XCTAssertEqual(forecast.activities[0].days.count, 7)
        XCTAssertEqual(forecast.activities[1].days.count, 8,
                       "two activities in one response can have different days.length")
    }

    func testHoursHaveNoHourFieldAndIndexIsPosition() throws {
        let forecast = try Fixtures.decodeForecast()
        // The wire shape has no `hour` key (dropped per ADR-0004); position comes from `index`.
        for (i, hour) in forecast.hours.enumerated() {
            XCTAssertEqual(hour.index, i)
            XCTAssertEqual(hour.id, i)
        }
    }

    func testNullableTrioDecodesNullToNil() throws {
        let forecast = try Fixtures.decodeForecast()
        let hour = forecast.hours[1] // fixture nulls the trio on hour 1
        XCTAssertNil(hour.windSpeed)
        XCTAssertNil(hour.rainFall)
        XCTAssertNil(hour.cloudCover)
        // and non-null hours decode values
        XCTAssertEqual(forecast.hours[0].windSpeed, 10)
        XCTAssertEqual(forecast.hours[0].rainFall, 0)
        XCTAssertEqual(forecast.hours[0].cloudCover, 15)
    }
}
