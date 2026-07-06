import XCTest
@testable import TimeIt

/// Pins the chip colour tiers from ios/guidelines/Guidelines.md ("Metric chip colour tiers").
final class MetricColorTests: XCTestCase {

    func testTempBoundaries() {
        XCTAssertEqual(MetricTier.tier(for: "temp", value: 18), .green)
        XCTAssertEqual(MetricTier.tier(for: "temp", value: 32), .green)
        XCTAssertEqual(MetricTier.tier(for: "temp", value: 33), .orange)
        XCTAssertEqual(MetricTier.tier(for: "temp", value: 37), .orange)
        XCTAssertEqual(MetricTier.tier(for: "temp", value: 38), .red)
    }

    func testUVBoundaries() {
        XCTAssertEqual(MetricTier.tier(for: "uV", value: 0), .green)
        XCTAssertEqual(MetricTier.tier(for: "uV", value: 3), .green)
        XCTAssertEqual(MetricTier.tier(for: "uV", value: 4), .orange)
        XCTAssertEqual(MetricTier.tier(for: "uV", value: 6), .orange)
        XCTAssertEqual(MetricTier.tier(for: "uV", value: 7), .red)
    }

    func testWindSpeedBoundaries() {
        XCTAssertEqual(MetricTier.tier(for: "windSpeed", value: 20), .green)
        XCTAssertEqual(MetricTier.tier(for: "windSpeed", value: 21), .orange)
        XCTAssertEqual(MetricTier.tier(for: "windSpeed", value: 35), .orange)
        XCTAssertEqual(MetricTier.tier(for: "windSpeed", value: 36), .red)
    }

    func testHumidityBoundaries() {
        XCTAssertEqual(MetricTier.tier(for: "humidity", value: 60), .green)
        XCTAssertEqual(MetricTier.tier(for: "humidity", value: 61), .orange)
        XCTAssertEqual(MetricTier.tier(for: "humidity", value: 75), .orange)
        XCTAssertEqual(MetricTier.tier(for: "humidity", value: 76), .red)
    }

    func testCloudCoverBoundaries() {
        XCTAssertEqual(MetricTier.tier(for: "cloudCover", value: 20), .green)
        XCTAssertEqual(MetricTier.tier(for: "cloudCover", value: 21), .orange)
        XCTAssertEqual(MetricTier.tier(for: "cloudCover", value: 60), .orange)
        XCTAssertEqual(MetricTier.tier(for: "cloudCover", value: 61), .red)
    }

    func testNilValueIsNeutral() {
        XCTAssertEqual(MetricTier.tier(for: "windSpeed", value: nil), .neutral)
        XCTAssertEqual(MetricTier.tier(for: "rainFall", value: nil), .neutral)
        XCTAssertEqual(MetricTier.tier(for: "cloudCover", value: nil), .neutral)
    }

    func testUntieredMetricIsNeutral() {
        // moon / dustAlert / rainFall have no numeric tier table — they stay neutral.
        XCTAssertEqual(MetricTier.tier(for: "moon", value: 1), .neutral)
        XCTAssertEqual(MetricTier.tier(for: "dustAlert", value: 0), .neutral)
    }
}
