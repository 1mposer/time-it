import XCTest
@testable import TimeIt

/// The ADR-0011 score mirror's pinning table.
///
/// **Shared pin:** `tests/fixtures/day-score-examples.json` — the server's
/// `src/decision/score.js` suite reads the same table. Following the
/// `clock-labels.json` precedent (`RangeTextTests`), the cases are
/// TRANSCRIBED here rather than loaded: the iOS target cannot reach the Node
/// test fixtures, and the expected values below were hand-computed from
/// ADR-0011's formula, never from the code under test. A drift between the
/// two sides is a release-blocking bug (ADR-0007's rule).
///
/// Only `metricCases` and `hourCases` are mirrored. `dayCases` are
/// server-only: the day score is read off the wire (`Day.score`) and must
/// never be recomputed on device.
final class DayScoreMirrorTests: XCTestCase {

    // MARK: metricCases — the per-metric depth-in-band score (0...100).
    // Required-ness plays no part at this level.

    func testTwoSidedCentre() {
        // min 10 / max 30, value 20 → the band centre.
        assertMetric(Threshold(min: 10, max: 30, required: true), .number(20), 100)
    }

    func testTwoSidedInsideLow() {
        // |15 − 20| = 5 of a half-width 10 → 100 × (1 − 0.5).
        assertMetric(Threshold(min: 10, max: 30, required: true), .number(15), 50)
    }

    func testTwoSidedInsideHigh() {
        // |27 − 20| = 7 of a half-width 10 → 100 × (1 − 0.7).
        assertMetric(Threshold(min: 10, max: 30, required: true), .number(27), 30)
    }

    func testTwoSidedMinEdge() {
        // ON the edge scores 0 for DEPTH — but it still PASSES the threshold
        // (see testAtBoundRequiredValueDoesNotZeroTheHour).
        assertMetric(Threshold(min: 10, max: 30, required: true), .number(10), 0)
    }

    func testTwoSidedMaxEdge() {
        assertMetric(Threshold(min: 10, max: 30, required: true), .number(30), 0)
    }

    func testTwoSidedOutsideBelow() {
        assertMetric(Threshold(min: 10, max: 30, required: true), .number(5), 0)
    }

    func testTwoSidedOutsideAbove() {
        assertMetric(Threshold(min: 10, max: 30, required: true), .number(35), 0)
    }

    func testMinOnlyInside() {
        // One-sided bands are BINARY (ADR-0011's recorded simplification).
        assertMetric(Threshold(min: 10, required: true), .number(50), 100)
    }

    func testMinOnlyAtBound() {
        assertMetric(Threshold(min: 10, required: true), .number(10), 100)
    }

    func testMinOnlyOutside() {
        assertMetric(Threshold(min: 10, required: true), .number(9), 0)
    }

    func testMaxOnlyInside() {
        assertMetric(Threshold(max: 30, required: true), .number(5), 100)
    }

    func testMaxOnlyAtBound() {
        assertMetric(Threshold(max: 30, required: true), .number(30), 100)
    }

    func testMaxOnlyOutside() {
        assertMetric(Threshold(max: 30, required: true), .number(31), 0)
    }

    func testFlagClear() {
        assertMetric(flagThreshold(required: true), .flag(false), 100)
    }

    func testFlagTripped() {
        assertMetric(flagThreshold(required: true), .flag(true), 0)
    }

    func testNullValue() {
        // The B2 rule — absent data scores 0, never passes silently.
        assertMetric(Threshold(min: 10, max: 30, required: true), .missing, 0)
    }

    // A ZERO-WIDTH band is legal on the wire — validation rejects min > max,
    // never min == max — and has no centre to measure depth from, so it takes
    // the same binary fallback as a one-sided band (server reference:
    // `src/decision/score.js`).

    func testDegenerateBandAtBound() {
        assertMetric(Threshold(min: 20, max: 20, required: true), .number(20), 100)
    }

    func testDegenerateBandOutside() {
        assertMetric(Threshold(min: 20, max: 20, required: true), .number(21), 0)
    }

    // MARK: hourCases — mean over the THRESHOLDED metrics; a required miss
    // zeroes the whole hour.

    func testRequiredMissZeroesHour() {
        assertHour(thresholds: ["temp": Threshold(min: 10, max: 30, required: true),
                                "windSpeed": Threshold(max: 20, required: false)],
                   values: ["temp": .number(35), "windSpeed": .number(10)],
                   expected: 0)
    }

    func testNullOnRequiredZeroesHour() {
        assertHour(thresholds: ["temp": Threshold(min: 10, max: 30, required: true),
                                "windSpeed": Threshold(max: 20, required: false)],
                   values: ["temp": .missing, "windSpeed": .number(10)],
                   expected: 0)
    }

    func testOptionalMissStillAverages() {
        // temp 20 → 100, windSpeed 25 (> max 20) → 0; mean 50.
        assertHour(thresholds: ["temp": Threshold(min: 10, max: 30, required: false),
                                "windSpeed": Threshold(max: 20, required: false)],
                   values: ["temp": .number(20), "windSpeed": .number(25)],
                   expected: 50)
    }

    func testDisplayOnlyMetricExcluded() {
        // displayMetrics = [temp, humidity] but only temp is thresholded, so
        // humidity never enters the mean: mean over one metric = 100.
        assertHour(thresholds: ["temp": Threshold(min: 10, max: 30, required: true)],
                   values: ["temp": .number(20), "humidity": .number(90)],
                   expected: 100)
    }

    func testNullOptionalDragsMean() {
        // A null on an OPTIONAL threshold scores 0 without zeroing the hour:
        // mean(0, 100) = 50.
        assertHour(thresholds: ["temp": Threshold(min: 10, max: 30, required: false),
                                "windSpeed": Threshold(max: 20, required: false)],
                   values: ["temp": .missing, "windSpeed": .number(10)],
                   expected: 50)
    }

    func testThreeMetricMean() {
        // temp 15 → 50, windSpeed 25 → 0, dustAlert false → 100; 150/3 = 50.
        assertHour(thresholds: ["temp": Threshold(min: 10, max: 30, required: false),
                                "windSpeed": Threshold(max: 20, required: false),
                                "dustAlert": flagThreshold(required: false)],
                   values: ["temp": .number(15), "windSpeed": .number(25), "dustAlert": .flag(false)],
                   expected: 50)
    }

    // MARK: the discriminating guard the shared table does not carry

    /// The required-miss rule is keyed on the threshold's PASS/FAIL predicate,
    /// never on `metricScore == 0`. A required value sitting exactly ON a
    /// bound scores 0 for depth yet PASSES (bounds are inclusive — the
    /// `HourQuality` mirror's semantics), so the hour must NOT be zeroed.
    /// Implementing the rule as "depth == 0 on a required metric" passes every
    /// case in the shared table and fails only here.
    func testAtBoundRequiredValueDoesNotZeroTheHour() {
        assertHour(thresholds: ["temp": Threshold(min: 10, max: 30, required: true),
                                "windSpeed": Threshold(max: 20, required: false)],
                   values: ["temp": .number(30), "windSpeed": .number(10)],
                   expected: 50) // mean(depth 0 at the edge, 100) — not 0.
    }

    /// The same trap on a one-sided required bound: 30 is ON `max` → passes.
    func testAtBoundRequiredOneSidedDoesNotZeroTheHour() {
        assertHour(thresholds: ["windSpeed": Threshold(max: 30, required: true)],
                   values: ["windSpeed": .number(30)],
                   expected: 100)
    }

    /// Shared table case `empty-thresholds-scores-100`. Show-but-don't-judge:
    /// an Activity with no thresholds has no mean to take — it scores 100,
    /// matching `HourQuality`'s empty-profile pass.
    func testEmptyThresholdsScores100() {
        assertHour(thresholds: [:], values: ["temp": .number(20)], expected: 100)
    }

    /// Validation-unreachable (a numeric threshold must carry ≥1 bound), but
    /// the mirror must not silently disagree with its reference: with no
    /// bound to fail, the server's `checkThreshold` passes and the score is
    /// 100. Kept aligned rather than recorded as an asymmetry.
    func testBoundLessNumericThresholdMatchesTheServerAt100() {
        assertMetric(Threshold(required: false), .number(20), 100)
    }

    // MARK: the hour convenience over a decoded HourlyWeather

    func testHourScoreReadsADecodedHour() {
        let hour = Fixtures.makeHour(index: 0, temp: 15, windSpeed: 25)
        let score = DayScore.hourScore(for: hour,
                                       thresholds: ["temp": Threshold(min: 10, max: 30, required: false),
                                                    "windSpeed": Threshold(max: 20, required: false)])
        XCTAssertEqual(score, 25, accuracy: 1e-9) // mean(50, 0)
    }

    func testHourScoreTreatsAMissingWireValueAsZero() {
        let hour = Fixtures.makeHour(index: 0, temp: nil, windSpeed: 10)
        let score = DayScore.hourScore(for: hour,
                                       thresholds: ["temp": Threshold(min: 10, max: 30, required: false),
                                                    "windSpeed": Threshold(max: 20, required: false)])
        XCTAssertEqual(score, 50, accuracy: 1e-9)
    }

    // MARK: helpers

    private func flagThreshold(required: Bool) -> Threshold {
        Threshold(required: required, type: "flag", forbidTrue: true)
    }

    private func assertMetric(_ threshold: Threshold,
                              _ value: MetricValue,
                              _ expected: Double,
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        XCTAssertEqual(DayScore.metricScore(threshold: threshold, value: value),
                       expected, accuracy: 1e-9, file: file, line: line)
    }

    private func assertHour(thresholds: [String: Threshold],
                            values: [String: MetricValue],
                            expected: Double,
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        XCTAssertEqual(DayScore.hourScore(values: values, thresholds: thresholds),
                       expected, accuracy: 1e-9, file: file, line: line)
    }
}
