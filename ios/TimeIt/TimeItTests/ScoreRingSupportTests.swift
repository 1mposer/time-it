import XCTest
@testable import TimeIt

/// The pure helpers behind card v2 and detail v3: the metric card's threshold
/// gauge, the card strip's boundary numerals, and the per-metric verdict that
/// colours a selected hour's value.
final class ScoreRingSupportTests: XCTestCase {

    private let catalog = StaticMetricCatalog()

    // MARK: MetricGauge — track = the catalog's metric domain

    func testPositionIsTheFractionOfTheDomain() {
        let domain = MetricRange(min: 0, max: 40, step: 1)
        XCTAssertEqual(MetricGauge.position(0, in: domain), 0, accuracy: 1e-9)
        XCTAssertEqual(MetricGauge.position(10, in: domain), 0.25, accuracy: 1e-9)
        XCTAssertEqual(MetricGauge.position(40, in: domain), 1, accuracy: 1e-9)
    }

    func testPositionClampsOutOfDomainReadings() {
        let domain = MetricRange(min: 0, max: 40, step: 1)
        XCTAssertEqual(MetricGauge.position(-5, in: domain), 0, accuracy: 1e-9)
        XCTAssertEqual(MetricGauge.position(99, in: domain), 1, accuracy: 1e-9)
    }

    func testTwoSidedBandSpansBothBounds() {
        // The frames' temperature card: a 15…35 band on the temp domain.
        let domain = try! XCTUnwrap(catalog.descriptor(for: "temp")?.range) // -10…50
        let span = try! XCTUnwrap(MetricGauge.bandSpan(threshold: Threshold(min: 15, max: 35, required: true),
                                                       in: domain))
        XCTAssertEqual(span.lowerBound, 25.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(span.upperBound, 45.0 / 60.0, accuracy: 1e-9)
    }

    func testMaxOnlyBandStartsAtTheDomainMinimum() {
        // The frames' wind card: a max-only band drawn from the track's start.
        let domain = try! XCTUnwrap(catalog.descriptor(for: "windSpeed")?.range) // 0…80
        let span = try! XCTUnwrap(MetricGauge.bandSpan(threshold: Threshold(max: 20, required: false),
                                                       in: domain))
        XCTAssertEqual(span.lowerBound, 0, accuracy: 1e-9)
        XCTAssertEqual(span.upperBound, 0.25, accuracy: 1e-9)
    }

    func testMinOnlyBandRunsToTheDomainMaximum() {
        let domain = try! XCTUnwrap(catalog.descriptor(for: "visibility")?.range) // 0…20
        let span = try! XCTUnwrap(MetricGauge.bandSpan(threshold: Threshold(min: 8, required: true),
                                                       in: domain))
        XCTAssertEqual(span.lowerBound, 0.4, accuracy: 1e-9)
        XCTAssertEqual(span.upperBound, 1, accuracy: 1e-9)
    }

    func testFlagThresholdHasNoBand() {
        let domain = MetricRange(min: 0, max: 10, step: 1)
        let flag = Threshold(required: true, type: "flag", forbidTrue: true)
        XCTAssertNil(MetricGauge.bandSpan(threshold: flag, in: domain))
        XCTAssertNil(MetricGauge.bandBounds(threshold: flag, in: domain))
    }

    func testBandBoundsFallBackToTheDomainEnds() {
        let domain = MetricRange(min: 0, max: 20, step: 0.5)
        let bounds = try! XCTUnwrap(MetricGauge.bandBounds(threshold: Threshold(max: 0.5, required: true),
                                                           in: domain))
        XCTAssertEqual(bounds.lower, 0, accuracy: 1e-9)
        XCTAssertEqual(bounds.upper, 0.5, accuracy: 1e-9)
    }

    func testNumeralsStayOnTheTrack() {
        let placed = MetricGauge.numeralPositions(lower: 0, upper: 1, trackWidth: 136)
        XCTAssertEqual(placed.lower, MetricGauge.numeralInset, accuracy: 1e-9)
        XCTAssertEqual(placed.upper, 136 - MetricGauge.numeralInset, accuracy: 1e-9)
    }

    /// A 0–0.2 mm rainfall threshold on a 0–20 mm domain puts both bounds at
    /// the same pixel — they must read "0" and "0.2", never overprint "002".
    func testNarrowBandNumeralsArePushedApart() {
        let placed = MetricGauge.numeralPositions(lower: 0, upper: 0.01, trackWidth: 136)
        XCTAssertGreaterThanOrEqual(placed.upper - placed.lower, MetricGauge.numeralGap - 1e-9)
        XCTAssertGreaterThanOrEqual(placed.lower, MetricGauge.numeralInset - 1e-9)
        XCTAssertLessThanOrEqual(placed.upper, 136 - MetricGauge.numeralInset + 1e-9)
    }

    func testAWideBandKeepsItsTrueNumeralPositions() {
        // 15…35 on the temp domain (-10…50) → 25/60 and 45/60 of 136pt, both
        // comfortably apart, so neither is nudged.
        let placed = MetricGauge.numeralPositions(lower: 25.0 / 60.0, upper: 45.0 / 60.0, trackWidth: 136)
        XCTAssertEqual(placed.lower, 136 * 25.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(placed.upper, 136 * 45.0 / 60.0, accuracy: 1e-9)
    }

    func testBoundTextTrimsWholeNumbers() {
        XCTAssertEqual(MetricGauge.boundText(15), "15")
        XCTAssertEqual(MetricGauge.boundText(0), "0")
        XCTAssertEqual(MetricGauge.boundText(0.5), "0.5")
    }

    // MARK: the gauge numerals speak the user's wind unit (#26)

    func testOnlyWindSpeedConvertsWithTheDisplayUnit() {
        XCTAssertEqual(MetricGauge.displayFactor(for: "windSpeed", windUnit: .kmh), 1, accuracy: 1e-9)
        XCTAssertEqual(MetricGauge.displayFactor(for: "windSpeed", windUnit: .knots),
                       WindSpeedUnit.knots.factorFromKmh, accuracy: 1e-9)
        XCTAssertEqual(MetricGauge.displayFactor(for: "temp", windUnit: .knots), 1, accuracy: 1e-9,
                       "a knots preference must not touch temperature")
        XCTAssertEqual(MetricGauge.displayFactor(for: "rainFall", windUnit: .knots), 1, accuracy: 1e-9)
    }

    /// A knots user who authored a 15 km/h wind cap must read the BAND bound
    /// in knots, under a value already shown in knots — never "15" under
    /// "8.1 kn". The conversion and its rounding are `ThresholdSlider`'s, so
    /// the gauge and the editor can never print different numbers for the
    /// same stored bound.
    func testKnotsUserReadsTheWindBandInKnots() {
        let factor = MetricGauge.displayFactor(for: "windSpeed", windUnit: .knots)
        XCTAssertEqual(MetricGauge.boundText(15, factor: factor), "8.1")
        XCTAssertEqual(MetricGauge.boundText(15, factor: factor),
                       ThresholdSlider.displayText(15, factor: factor),
                       "one conversion home with the threshold editor")
        XCTAssertEqual(MetricGauge.boundText(15), "15", "a km/h user still reads 15")
    }

    func testTheGaugeGeometryStaysInWireUnits() {
        // Only the numerals convert — the band is a ratio of the metric's
        // domain, so a knots preference must not move it.
        let domain = try! XCTUnwrap(catalog.descriptor(for: "windSpeed")?.range) // 0…80
        let span = try! XCTUnwrap(MetricGauge.bandSpan(threshold: Threshold(max: 20, required: false),
                                                       in: domain))
        XCTAssertEqual(span.upperBound, 0.25, accuracy: 1e-9)
    }

    // MARK: RangeStripAxis — the card strip's boundary numerals

    func testNumeralsUseTheBare12HourStyle() {
        XCTAssertEqual(RangeStripAxis.numeral(6), "6")
        XCTAssertEqual(RangeStripAxis.numeral(10), "10")
        XCTAssertEqual(RangeStripAxis.numeral(12), "12")
        XCTAssertEqual(RangeStripAxis.numeral(15), "3")
        XCTAssertEqual(RangeStripAxis.numeral(0), "12")
        XCTAssertEqual(RangeStripAxis.numeral(24), "12", "the strip counts past midnight")
        XCTAssertEqual(RangeStripAxis.numeral(26), "2")
    }

    func testTheApprovedFrameStripPrintsEveryBoundary() {
        // Frame 458:394 — a 6–10am Range: four segments, five numerals.
        let labels = RangeStripAxis.labels(startLocalHour: 6, hourCount: 4)
        XCTAssertEqual(labels.map(\.text), ["6", "7", "8", "9", "10"])
        XCTAssertEqual(labels.map(\.boundary), [0, 1, 2, 3, 4])
    }

    func testTheNullStateStripPrintsEveryBoundary() {
        // Frame 458:394, second card — a 6–9am Range.
        XCTAssertEqual(RangeStripAxis.labels(startLocalHour: 6, hourCount: 3).map(\.text),
                       ["6", "7", "8", "9"])
    }

    func testANocturnalStripCountsAcrossMidnight() {
        XCTAssertEqual(RangeStripAxis.labels(startLocalHour: 22, hourCount: 4).map(\.text),
                       ["10", "11", "12", "1", "2"])
    }

    func testLongRangesThinTheirNumeralsButKeepBothEnds() {
        let boundaries = RangeStripAxis.visibleBoundaries(hourCount: 24)
        XCTAssertEqual(boundaries.first, 0)
        XCTAssertEqual(boundaries.last, 24)
        XCTAssertLessThanOrEqual(boundaries.count, RangeStripAxis.maxLabels + 1)
        XCTAssertEqual(boundaries, boundaries.sorted())
        XCTAssertEqual(Set(boundaries).count, boundaries.count, "no duplicate boundary")
    }

    func testAnEmptyStripHasNoNumerals() {
        XCTAssertTrue(RangeStripAxis.visibleBoundaries(hourCount: 0).isEmpty)
    }

    // MARK: HourQuality.metricTier — what colours a metric card's value

    func testAPassingMetricReadsGreen() {
        let hour = Fixtures.makeHour(index: 0, temp: 24)
        XCTAssertEqual(HourQuality.metricTier(for: hour, metric: "temp",
                                              threshold: Threshold(min: 15, max: 35, required: true)),
                       .green)
    }

    func testAFailedOptionalMetricReadsOrange() {
        // The frames' wind card: 27 km/h against an optional max of 15.
        let hour = Fixtures.makeHour(index: 0, windSpeed: 27)
        XCTAssertEqual(HourQuality.metricTier(for: hour, metric: "windSpeed",
                                              threshold: Threshold(max: 15, required: false)),
                       .orange)
    }

    func testAFailedRequiredMetricReadsRed() {
        let hour = Fixtures.makeHour(index: 0, temp: 42)
        XCTAssertEqual(HourQuality.metricTier(for: hour, metric: "temp",
                                              threshold: Threshold(min: 15, max: 35, required: true)),
                       .red)
    }

    func testAnAtBoundValuePasses() {
        // Inclusive bounds — the same semantics the score mirror's
        // required-miss rule routes through.
        let hour = Fixtures.makeHour(index: 0, temp: 35)
        XCTAssertEqual(HourQuality.metricTier(for: hour, metric: "temp",
                                              threshold: Threshold(min: 15, max: 35, required: true)),
                       .green)
    }

    func testAMissingValueFailsItsThreshold() {
        let hour = Fixtures.makeHour(index: 0, temp: nil)
        XCTAssertEqual(HourQuality.metricTier(for: hour, metric: "temp",
                                              threshold: Threshold(min: 15, max: 35, required: false)),
                       .orange)
    }

    func testAnUnthresholdedMetricIsNotJudged() {
        // Show-but-don't-judge renders uncoloured, never a free green.
        let hour = Fixtures.makeHour(index: 0, humidity: 90)
        XCTAssertNil(HourQuality.metricTier(for: hour, metric: "humidity", threshold: nil))
    }

    // MARK: Theme.ratingTint — the ring's colour follows the day's tier

    func testRingTintFollowsTheRatingTier() {
        XCTAssertEqual(Theme.ratingTint(.perfect), Theme.perfectGreen)
        XCTAssertEqual(Theme.ratingTint(.good), Theme.accentOrange)
        XCTAssertEqual(Theme.ratingTint(nil), Theme.badRed)
        XCTAssertEqual(Theme.ratingTint(.unknown("legendary")), Theme.badRed,
                       "an unknown verdict must never paint favourably")
    }
}
