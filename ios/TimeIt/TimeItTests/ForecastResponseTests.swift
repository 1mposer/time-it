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
        XCTAssertEqual(forecast.hours[0].windSpeed, 10)
        XCTAssertEqual(forecast.hours[0].rainFall, 0)
        XCTAssertEqual(forecast.hours[0].cloudCover, 15)
    }

    // Guards the 2026-07-12 live decode bug: Meteosource's uv_index: null at
    // night threw on the non-nullable uV and blanked the WHOLE dashboard.
    func testNullUVDecodesToNilWithoutFailingTheWholeResponse() throws {
        let forecast = try Fixtures.decodeForecast() // hour 2 has uV: null
        XCTAssertEqual(forecast.hours.count, 60, "a null uV must not abort the decode")
        XCTAssertNil(forecast.hours[2].uV)
        XCTAssertEqual(forecast.hours[2].formatted(for: "uV"), "—")
        XCTAssertEqual(forecast.hours[0].uV, 3)
    }
}
