import XCTest
@testable import TimeIt

/// The detail metric cards average the carousel's chosen hours (owner ruling
/// 2026-11-01). Numeric = mean of non-nil, flags = any true, label = the
/// span's first hour.
final class HourAggregateTests: XCTestCase {

    private func hour(_ index: Int,
                      temp: Double? = 24,
                      windSpeed: Double? = 10,
                      dust: Bool = false,
                      sea: Bool = false,
                      moon: [String] = ["waxing crescent"]) -> HourlyWeather {
        HourlyWeather(index: index, temp: temp, humidity: 40, visibility: 10, uV: 3,
                      windSpeed: windSpeed, rainFall: 0, cloudCover: 15,
                      moon: moon, dustAlert: dust, seaWarning: sea,
                      darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0, tide: 0)
    }

    func testNoHoursIsNil() {
        XCTAssertNil(HourAggregate.aggregate([]))
    }

    func testASingleHourSpanEqualsThatHour() {
        let only = hour(7, temp: 21.4, windSpeed: nil, dust: true)
        let result = HourAggregate.aggregate([only])
        XCTAssertEqual(result?.index, 7)
        XCTAssertEqual(result?.temp, 21.4)
        XCTAssertNil(result?.windSpeed)
        XCTAssertEqual(result?.dustAlert, true)
        XCTAssertEqual(result?.formatted(for: "temp"), only.formatted(for: "temp"))
    }

    func testNumericIsTheMeanOfTheNonNilValues() {
        // (20 + 26) / 2 = 23 — the nil hour is skipped, not counted as 0.
        let result = HourAggregate.aggregate([hour(2, temp: 20), hour(3, temp: nil), hour(4, temp: 26)])
        XCTAssertEqual(result?.temp, 23)
        XCTAssertEqual(result?.index, 2, "the span's first hour")
    }

    func testAllNilIsNilAndRendersADash() {
        let result = HourAggregate.aggregate([hour(0, windSpeed: nil), hour(1, windSpeed: nil)])
        XCTAssertNil(result?.windSpeed)
        XCTAssertEqual(result?.formatted(for: "windSpeed"), "—")
    }

    func testTheMeanIsRoundedOnlyByTheCardsFormatter() {
        // (20 + 21) / 2 = 20.5 → kept unrounded, formatted half-away → "21°C".
        let result = HourAggregate.aggregate([hour(0, temp: 20), hour(1, temp: 21)])
        XCTAssertEqual(result?.temp, 20.5)
        XCTAssertEqual(result?.formatted(for: "temp"), "21°C")
        // (20 + 20 + 21) / 3 = 20.33… → "20°C".
        let third = HourAggregate.aggregate([hour(0, temp: 20), hour(1, temp: 20), hour(2, temp: 21)])
        XCTAssertEqual(third?.formatted(for: "temp"), "20°C")
    }

    func testFlagsAreTrueIfAnyChosenHourIsTrue() {
        let none = HourAggregate.aggregate([hour(0), hour(1), hour(2)])
        XCTAssertEqual(none?.dustAlert, false)
        XCTAssertEqual(none?.seaWarning, false)
        let some = HourAggregate.aggregate([hour(0), hour(1, dust: true), hour(2, sea: true)])
        XCTAssertEqual(some?.dustAlert, true)
        XCTAssertEqual(some?.seaWarning, true)
    }

    func testTheLabelMetricReadsTheSpansFirstHour() {
        let result = HourAggregate.aggregate([hour(0, moon: ["full moon"]), hour(1, moon: ["last quarter"])])
        XCTAssertEqual(result?.moon, ["full moon"])
        XCTAssertEqual(result?.formatted(for: "moon"), "Full moon", "sentence case on display (note 21)")
    }
}
