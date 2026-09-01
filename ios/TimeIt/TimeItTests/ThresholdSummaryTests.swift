import XCTest
@testable import TimeIt

/// Metrics + thresholds stated once as one compact block — "Temp 15 – 32°C
/// required · Wind ≤ 25 km/h optional · …": short metric names, unit once
/// (glued for °C/%, spaced for word units), ≤/≥ for one-sided bounds, entries
/// in displayMetrics order.
final class ThresholdSummaryTests: XCTestCase {

    func testCyclingSummaryMatchesTheApprovedFrame() {
        XCTAssertEqual(ThresholdSummary.line(for: Fixtures.cycling),
                       "Temp 15 – 32°C required · Wind ≤ 25 km/h optional · Rain ≤ 0.2 mm required · UV ≤ 8 optional")
    }

    func testSummarySkipsUnthresholdedMetricsAndUsesMinBound() {
        // moon is display-only (show-but-don't-judge) — never in the summary;
        // visibility has only a min → "≥".
        let activity = AuthoredActivity(
            id: "night-fixture",
            label: "Night Fixture",
            iconSymbol: "moon.stars.fill",
            templateOrigin: nil,
            displayMetrics: ["cloudCover", "moon", "temp", "visibility"],
            thresholds: [
                "cloudCover": Threshold(max: 20, required: true),
                "temp": Threshold(min: 8, max: 35, required: false),
                "visibility": Threshold(min: 8, required: false),
            ],
            window: WindowSpec(startHour: 22, endHour: 4))
        XCTAssertEqual(ThresholdSummary.line(for: activity),
                       "Cloud ≤ 20% required · Temp 8 – 35°C optional · Visibility ≥ 8 km optional")
    }

    func testEntriesFollowDisplayMetricsOrder() {
        var activity = Fixtures.fishingLite
        activity.displayMetrics = ["cloudCover", "windSpeed", "temp"]
        XCTAssertEqual(ThresholdSummary.line(for: activity),
                       "Cloud ≤ 80% optional · Wind ≤ 25 km/h required · Temp 12 – 36°C required")
    }

    func testFlagThresholdReadsAsAlertFree() {
        var activity = Fixtures.cycling
        activity.displayMetrics = ["temp", "dustAlert"]
        activity.thresholds = [
            "temp": Threshold(min: 15, max: 32, required: true),
            "dustAlert": Threshold(required: true, type: "flag", forbidTrue: true),
        ]
        XCTAssertEqual(ThresholdSummary.line(for: activity),
                       "Temp 15 – 32°C required · No dust alerts required")
    }

    func testNoThresholdsProducesNil() {
        var activity = Fixtures.cycling
        activity.thresholds = [:]
        XCTAssertNil(ThresholdSummary.line(for: activity),
                     "an all-display profile has nothing to state — the block hides")
    }

    func testWholeNumbersDropTheDecimalPoint() {
        var activity = Fixtures.cycling
        activity.displayMetrics = ["rainFall"]
        activity.thresholds = ["rainFall": Threshold(max: 2.0, required: true)]
        XCTAssertEqual(ThresholdSummary.line(for: activity), "Rain ≤ 2 mm required")
    }
}
