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

    func testHumanLabelsComeFromTheCatalog() {
        // The catalog is the ONLY metric name table (HourlyWeather's own copy
        // drifted from it and was removed) — chips and the editor now show
        // the same name for the same metric.
        let catalog = StaticMetricCatalog()
        XCTAssertEqual(catalog.displayName(for: "temp"), "Temperature")
        XCTAssertEqual(catalog.displayName(for: "windSpeed"), "Wind Speed")
        XCTAssertEqual(catalog.displayName(for: "rainFall"), "Rainfall")
        XCTAssertEqual(catalog.displayName(for: "uV"), "UV Index")
        XCTAssertEqual(catalog.displayName(for: "cloudCover"), "Cloud Cover")
        XCTAssertEqual(catalog.displayName(for: "humidity"), "Humidity")
        XCTAssertEqual(catalog.displayName(for: "swellHeight"), "swellHeight",
                       "unknown keys fall back to the key itself, never crash")
    }
}
