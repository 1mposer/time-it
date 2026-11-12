import XCTest
@testable import TimeIt

/// Pins mph as the third wind unit (fresh-eyes row 14a, owner 2026-11-12):
/// display-only like knots — every stored limit and the wire stay km/h.
/// 1 mi = 1.609344 km exactly (international mile).
final class UnitsTests: XCTestCase {

    func testMphConversion() {
        XCTAssertEqual(WindSpeedUnit.mph.fromKmh(1.609344), 1, accuracy: 1e-12, "1 mph = 1.609344 km/h")
        XCTAssertEqual(WindSpeedUnit.mph.toKmh(10), 16.09344, accuracy: 1e-12)
        XCTAssertEqual(WindSpeedUnit.mph.fromKmh(25), 15.534, accuracy: 0.001)
        for kmh in [0.0, 7.0, 25.0, 80.0] {
            XCTAssertEqual(WindSpeedUnit.mph.toKmh(WindSpeedUnit.mph.fromKmh(kmh)), kmh, accuracy: 1e-9)
        }
    }

    func testMphCopyAndPersistence() {
        XCTAssertEqual(WindSpeedUnit.mph.label, "mph")
        XCTAssertEqual(WindSpeedUnit.mph.displayName, "mph")
        XCTAssertEqual(WindSpeedUnit.mph.rawValue, "mph")
        XCTAssertEqual(WindSpeedUnit.allCases, [.kmh, .knots, .mph], "the Settings picker order")
    }

    func testMphReachesEveryWindSurface() {
        // Chips / metric cards.
        let hour = Fixtures.makeHour(index: 0, windSpeed: 13)
        XCTAssertEqual(hour.formatted(for: "windSpeed", windUnit: .mph), "8 mph", "13 km/h ≈ 8.08 mph")
        // Header meta line.
        XCTAssertEqual(HeaderCopy.metaSegments(clock: "9:41", windKmh: 25, humidity: nil, windUnit: .mph),
                       [.clock("9:41"), .wind("16 mph")])
        // Gauges.
        XCTAssertEqual(MetricGauge.displayFactor(for: "windSpeed", windUnit: .mph), 1 / 1.609344, accuracy: 1e-12)
    }

    func testWholeMphRoundTripThroughTheOneDecimalStore() {
        let mph = WindSpeedUnit.mph.factorFromKmh
        for typed in ["1", "5", "9", "12", "15", "20", "25", "31", "40", "50"] {
            let stored = ThresholdSlider.storageText(typed, factor: mph)
            XCTAssertEqual(ThresholdSlider.displayText(Double(stored)!, factor: mph), typed,
                           "typing \(typed) mph must read back as \(typed) mph (stored \(stored) km/h)")
        }
    }
}
