import XCTest
@testable import TimeIt

final class HourlyWeatherFormattedTests: XCTestCase {

    func testNullableMetricsFormatAsEmDashWhenNil() {
        let hour = Fixtures.makeHour(index: 0, windSpeed: nil, rainFall: nil, cloudCover: nil)
        XCTAssertEqual(hour.formatted(for: "windSpeed"), "—")
        XCTAssertEqual(hour.formatted(for: "rainFall"), "—")
        XCTAssertEqual(hour.formatted(for: "cloudCover"), "—")
    }

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

    // Note 21: the wire's lowercase phase reads in sentence case, like
    // every other label — "New moon", not "new moon" (nor "New Moon").
    func testMoonPhaseReadsInSentenceCase() {
        let newMoon = HourlyWeather(index: 0, temp: 24, humidity: 40, visibility: 10, uV: 0,
                                    windSpeed: 10, rainFall: 0, cloudCover: 15,
                                    moon: ["new moon"], dustAlert: false, seaWarning: false,
                                    darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0, tide: 0)
        XCTAssertEqual(newMoon.formatted(for: "moon"), "New moon")
        XCTAssertEqual(Fixtures.makeHour(index: 0).formatted(for: "moon"), "Waxing crescent")
        let none = HourlyWeather(index: 0, temp: 24, humidity: 40, visibility: 10, uV: 0,
                                 windSpeed: 10, rainFall: 0, cloudCover: 15,
                                 moon: [], dustAlert: false, seaWarning: false,
                                 darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0, tide: 0)
        XCTAssertEqual(none.formatted(for: "moon"), "—")
    }

    // #26: wind speed renders in the chosen unit; the value stays km/h.
    func testWindSpeedFormatsInKnotsWhenAsked() {
        let hour = Fixtures.makeHour(index: 0, windSpeed: 13)
        XCTAssertEqual(hour.formatted(for: "windSpeed", windUnit: .knots), "7 kn", "13 km/h ≈ 7.02 kn")
        XCTAssertEqual(hour.formatted(for: "windSpeed", windUnit: .kmh), "13 km/h")
        XCTAssertEqual(hour.formatted(for: "windSpeed"), "13 km/h", "km/h stays the default")
    }

    func testWindUnitLeavesEveryOtherMetricAlone() {
        let hour = Fixtures.makeHour(index: 0, temp: 22.4, windSpeed: nil, rainFall: 0.2)
        XCTAssertEqual(hour.formatted(for: "windSpeed", windUnit: .knots), "—")
        XCTAssertEqual(hour.formatted(for: "temp", windUnit: .knots), "22°C")
        XCTAssertEqual(hour.formatted(for: "rainFall", windUnit: .knots), "0.2 mm")
    }

    func testWholeNumberRainFallHasNoDecimal() {
        let hour = Fixtures.makeHour(index: 0, rainFall: 0)
        XCTAssertEqual(hour.formatted(for: "rainFall"), "0 mm")
    }

    func testUnknownMetricFormatsAsEmDash() {
        XCTAssertEqual(Fixtures.makeHour(index: 0).formatted(for: "swellHeight"), "—")
    }

    func testHumanLabelsComeFromTheCatalog() {
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
