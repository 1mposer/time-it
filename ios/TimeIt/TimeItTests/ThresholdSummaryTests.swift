import XCTest
@testable import TimeIt

/// Metrics + thresholds stated once as one compact block — "Temp 15 – 32°C
/// required · Wind ≤ 25 km/h optional · …": short metric names, unit once
/// (glued for °C/%, spaced for word units), ≤/≥ for one-sided bounds, entries
/// in displayMetrics order.
final class ThresholdSummaryTests: XCTestCase {

    func testCyclingSummaryMatchesTheApprovedFrame() {
        XCTAssertEqual(ThresholdSummary.line(for: SeedTemplates.cycling),
                       "Temp 15 – 32°C required · Wind ≤ 25 km/h optional · Rain ≤ 0.2 mm required · UV ≤ 8 optional")
    }

    func testStargazingSummarySkipsUnthresholdedMetricsAndUsesMinBound() {
        // moon is display-only (show-but-don't-judge) — never in the summary;
        // visibility has only a min → "≥".
        XCTAssertEqual(ThresholdSummary.line(for: SeedTemplates.stargazing),
                       "Cloud ≤ 20% required · Temp 8 – 35°C optional · Visibility ≥ 8 km optional")
    }

    func testEntriesFollowDisplayMetricsOrder() {
        var activity = SeedTemplates.fishingLite
        activity.displayMetrics = ["cloudCover", "windSpeed", "temp"]
        XCTAssertEqual(ThresholdSummary.line(for: activity),
                       "Cloud ≤ 80% optional · Wind ≤ 25 km/h required · Temp 12 – 36°C required")
    }

    func testFlagThresholdReadsAsAlertFree() {
        var activity = SeedTemplates.cycling
        activity.displayMetrics = ["temp", "dustAlert"]
        activity.thresholds = [
            "temp": Threshold(min: 15, max: 32, required: true),
            "dustAlert": Threshold(required: true, type: "flag", forbidTrue: true),
        ]
        XCTAssertEqual(ThresholdSummary.line(for: activity),
                       "Temp 15 – 32°C required · No dust alerts required")
    }

    func testNoThresholdsProducesNil() {
        var activity = SeedTemplates.cycling
        activity.thresholds = [:]
        XCTAssertNil(ThresholdSummary.line(for: activity),
                     "an all-display profile has nothing to state — the block hides")
    }

    func testWholeNumbersDropTheDecimalPoint() {
        var activity = SeedTemplates.cycling
        activity.displayMetrics = ["rainFall"]
        activity.thresholds = ["rainFall": Threshold(max: 2.0, required: true)]
        XCTAssertEqual(ThresholdSummary.line(for: activity), "Rain ≤ 2 mm required")
    }
}
