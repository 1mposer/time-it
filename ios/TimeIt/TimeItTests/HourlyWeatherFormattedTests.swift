import XCTest
@testable import TimeIt

final class HourlyWeatherFormattedTests: XCTestCase {

    func testNullableMetricsFormatAsEmDashWhenNil() {
        let hour = Fixtures.makeHour(index: 0, windSpeed: nil, rainFall: nil, cloudCover: nil)
        XCTAssertEqual(hour.formatted(for: "windSpeed"), "—")
        XCTAssertEqual(hour.formatted(for: "rainFall"), "—")
        XCTAssertEqual(hour.formatted(for: "cloudCover"), "—")
    }

    // Every metric is now null-tolerant, not just the wind/rain/cloud trio — a
    // null temp/humidity/visibility/uV renders "—" instead of blanking the app.
    func testCoreMetricsFormatAsEmDashWhenNil() {
        let hour = Fixtures.makeHour(index: 0, temp: nil, humidity: nil, visibility: nil, uV: nil)
        XCTAssertEqual(hour.formatted(for: "temp"), "—")
        XCTAssertEqual(hour.formatted(for: "humidity"), "—")
        XCTAssertEqual(hour.formatted(for: "visibility"), "—")
        XCTAssertEqual(hour.formatted(for: "uV"), "—")
    }

    func testFormatsValuesWhenPresent() {
        let hour = Fixtures.makeHour(index: 0, temp: 22.4, humidity: 8, uV: 3, windSpeed: 13, rainFall: 0.2, cloudCover: 25)
        XCTAssertEqual(hour.formatted(for: "temp"), "22°C")
        XCTAssertEqual(hour.formatted(for: "windSpeed"), "13 km/h")
        XCTAssertEqual(hour.formatted(for: "uV"), "UV 3")
        XCTAssertEqual(hour.formatted(for: "humidity"), "8%")
        XCTAssertEqual(hour.formatted(for: "cloudCover"), "25%")
        XCTAssertEqual(hour.formatted(for: "rainFall"), "0.2 mm")
        XCTAssertEqual(hour.formatted(for: "visibility"), "10 km")
    }

    func testWholeNumberRainFallHasNoDecimal() {
        let hour = Fixtures.makeHour(index: 0, rainFall: 0)
        XCTAssertEqual(hour.formatted(for: "rainFall"), "0 mm")
    }

    func testUnknownMetricFormatsAsEmDash() {
        XCTAssertEqual(Fixtures.makeHour(index: 0).formatted(for: "swellHeight"), "—")
    }

    func testHumanLabels() {
        XCTAssertEqual(HourlyWeather.label(for: "temp"), "Temperature")
        XCTAssertEqual(HourlyWeather.label(for: "windSpeed"), "Wind")
        XCTAssertEqual(HourlyWeather.label(for: "rainFall"), "Rain")
        XCTAssertEqual(HourlyWeather.label(for: "uV"), "UV Index")
        XCTAssertEqual(HourlyWeather.label(for: "cloudCover"), "Cloud Cover")
        XCTAssertEqual(HourlyWeather.label(for: "humidity"), "Humidity")
    }
}
