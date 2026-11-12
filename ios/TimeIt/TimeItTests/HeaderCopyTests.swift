import XCTest
@testable import TimeIt

/// Pins `HeaderCopy` — the header numeral swap (FIGMA.md §12 ruling 7): the
/// temperature is the big numeral, with its unit ("34°C" — fresh-eyes row
/// 18a, owner 2026-11-12, as the approved onboarding dashboard frame draws
/// it), and the meta line reads clock, wind, humidity in that order. Figma
/// draws no separator glyph: each metric is its own icon + value group, so a
/// missing metric drops its whole segment.
final class HeaderCopyTests: XCTestCase {

    // MARK: - Numeral

    func testUnitSuffix() {
        XCTAssertEqual(HeaderCopy.numeral(temp: 28), "28°C")
        XCTAssertEqual(HeaderCopy.numeral(temp: 33.6), "34°C")
        XCTAssertEqual(HeaderCopy.numeral(temp: 33.4), "33°C")
    }

    func testNumeralKeepsTheSignOfANegativeTemperature() {
        XCTAssertEqual(HeaderCopy.numeral(temp: -3.2), "-3°C")
        XCTAssertEqual(HeaderCopy.numeral(temp: -12.5), "-13°C", "half away from zero, like the rest of the app")
    }

    func testMissingTemperatureRendersADashNumeral() {
        XCTAssertEqual(HeaderCopy.numeral(temp: nil), "—°", "no reading claims no unit")
    }

    // MARK: - Meta line

    func testMetaLineReadsClockThenWindThenHumidity() {
        let segments = HeaderCopy.metaSegments(clock: "10:16 AM", windKmh: 10, humidity: 40, windUnit: .kmh)
        XCTAssertEqual(segments, [.clock("10:16 AM"), .wind("10 km/h"), .humidity("40%")])
    }

    func testMetaLineConvertsWindToThePreferredUnit() {
        let segments = HeaderCopy.metaSegments(clock: "9:41", windKmh: 18, humidity: 55.4, windUnit: .knots)
        XCTAssertEqual(segments, [.clock("9:41"),
                                  .wind("\(Int(WindSpeedUnit.knots.fromKmh(18).rounded())) \(WindSpeedUnit.knots.label)"),
                                  .humidity("55%")])
    }

    func testMissingWindOrHumidityDropsItsSegment() {
        XCTAssertEqual(HeaderCopy.metaSegments(clock: "9:41", windKmh: nil, humidity: 55, windUnit: .kmh),
                       [.clock("9:41"), .humidity("55%")])
        XCTAssertEqual(HeaderCopy.metaSegments(clock: "9:41", windKmh: 18, humidity: nil, windUnit: .kmh),
                       [.clock("9:41"), .wind("18 km/h")])
        XCTAssertEqual(HeaderCopy.metaSegments(clock: "9:41", windKmh: nil, humidity: nil, windUnit: .kmh),
                       [.clock("9:41")], "the clock always stays — it is not weather")
    }
}
