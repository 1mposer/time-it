import XCTest
@testable import TimeIt

/// Pins `HeaderCopy` — the header numeral swap (FIGMA.md §12 ruling 7): the
/// temperature is the big numeral ("34°", no unit letter — the Figma
/// numeral drops it), and the meta line reads clock, wind, humidity in that
/// order. Figma draws no separator glyph: each metric is its own icon +
/// value group, so a missing metric drops its whole segment.
final class HeaderCopyTests: XCTestCase {

    // MARK: - Numeral

    func testNumeralRoundsTheTemperatureAndDropsTheUnitLetter() {
        XCTAssertEqual(HeaderCopy.numeral(temp: 24), "24°")
        XCTAssertEqual(HeaderCopy.numeral(temp: 33.6), "34°")
        XCTAssertEqual(HeaderCopy.numeral(temp: 33.4), "33°")
    }

    func testNumeralKeepsTheSignOfANegativeTemperature() {
        XCTAssertEqual(HeaderCopy.numeral(temp: -3.2), "-3°")
        XCTAssertEqual(HeaderCopy.numeral(temp: -12.5), "-13°", "half away from zero, like the rest of the app")
    }

    func testMissingTemperatureRendersADashNumeral() {
        XCTAssertEqual(HeaderCopy.numeral(temp: nil), "—°")
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
