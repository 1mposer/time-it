import XCTest
@testable import TimeIt

/// Spec 14 §3: the on-device per-hour evaluator — the client-side mirror of the
/// server's `evaluateHour`/`checkThreshold` (`src/decision/decision_engine.js`),
/// ADR-0007 mirror #3. Required fail → red, optional-only fail → orange, all
/// pass → green; absent data FAILS its threshold (the B2 rule); flags fail on
/// `true`.
final class HourQualityTests: XCTestCase {

    private func tier(_ hour: HourlyWeather, _ thresholds: [String: Threshold]) -> HourTier {
        HourQuality.tier(for: hour, thresholds: thresholds)
    }

    // MARK: the three-way verdict

    func testAllThresholdsPassIsGreen() {
        let hour = Fixtures.makeHour(index: 0, temp: 24, windSpeed: 10)
        let thresholds = [
            "temp": Threshold(min: 15, max: 32, required: true),
            "windSpeed": Threshold(max: 25, required: false),
        ]
        XCTAssertEqual(tier(hour, thresholds), .green)
    }

    func testOnlyOptionalFailureIsOrange() {
        let hour = Fixtures.makeHour(index: 0, temp: 24, windSpeed: 40)
        let thresholds = [
            "temp": Threshold(min: 15, max: 32, required: true),
            "windSpeed": Threshold(max: 25, required: false),
        ]
        XCTAssertEqual(tier(hour, thresholds), .orange)
    }

    func testRequiredFailureIsRedEvenWhenEverythingElsePasses() {
        let hour = Fixtures.makeHour(index: 0, temp: 40, windSpeed: 10)
        let thresholds = [
            "temp": Threshold(min: 15, max: 32, required: true),
            "windSpeed": Threshold(max: 25, required: false),
        ]
        XCTAssertEqual(tier(hour, thresholds), .red)
    }

    func testEmptyThresholdsIsGreen() {
        // Show-but-don't-judge: nothing to fail = perfect, per the server.
        XCTAssertEqual(tier(Fixtures.makeHour(index: 0), [:]), .green)
    }

    // MARK: B2 — absent data fails, never silently passes

    func testNilValueFailsARequiredThresholdToRed() {
        let hour = Fixtures.makeHour(index: 0, windSpeed: nil)
        let thresholds = ["windSpeed": Threshold(max: 25, required: true)]
        XCTAssertEqual(tier(hour, thresholds), .red)
    }

    func testNilValueFailsAnOptionalThresholdToOrange() {
        let hour = Fixtures.makeHour(index: 0, windSpeed: nil)
        let thresholds = ["windSpeed": Threshold(max: 25, required: false)]
        XCTAssertEqual(tier(hour, thresholds), .orange)
    }

    func testUnknownMetricKeyFailsItsThreshold() {
        // Server: hourData[metric] is undefined → checkThreshold fails. The
        // mirror must not treat an unmapped key as a pass.
        let thresholds = ["sharknado": Threshold(max: 1, required: true)]
        XCTAssertEqual(tier(Fixtures.makeHour(index: 0), thresholds), .red)
    }

    // MARK: flag thresholds

    func testRaisedFlagFailsForbidTrue() {
        var hour = Fixtures.makeHour(index: 0)
        hour = HourlyWeather(index: 0, temp: 24, humidity: 40, visibility: 10,
                             uV: 3, windSpeed: 10, rainFall: 0, cloudCover: 15,
                             moon: [], dustAlert: true, seaWarning: false,
                             darkness: 0, douglasScale: 0, swellHeight: 0,
                             swellLength: 0, tide: 0)
        let required = ["dustAlert": Threshold(required: true, type: "flag", forbidTrue: true)]
        XCTAssertEqual(tier(hour, required), .red)

        let optional = ["dustAlert": Threshold(required: false, type: "flag", forbidTrue: true)]
        XCTAssertEqual(tier(hour, optional), .orange)
    }

    func testLoweredFlagPasses() {
        let hour = Fixtures.makeHour(index: 0) // dustAlert: false
        let thresholds = ["dustAlert": Threshold(required: true, type: "flag", forbidTrue: true)]
        XCTAssertEqual(tier(hour, thresholds), .green)
    }

    // MARK: inclusive bounds (mirror uses strict < min / > max, like the server)

    func testBoundaryValuesAreInclusive() {
        let atMin = Fixtures.makeHour(index: 0, temp: 15)
        let atMax = Fixtures.makeHour(index: 0, temp: 32)
        let belowMin = Fixtures.makeHour(index: 0, temp: 14.9)
        let aboveMax = Fixtures.makeHour(index: 0, temp: 32.1)
        let thresholds = ["temp": Threshold(min: 15, max: 32, required: true)]

        XCTAssertEqual(tier(atMin, thresholds), .green, "value == min passes")
        XCTAssertEqual(tier(atMax, thresholds), .green, "value == max passes")
        XCTAssertEqual(tier(belowMin, thresholds), .red)
        XCTAssertEqual(tier(aboveMax, thresholds), .red)
    }

    // MARK: tier ordering (red < orange < green — spec 14 vocabulary)

    func testTierOrderingMatchesSpecVocabulary() {
        XCTAssertLessThan(HourTier.red, .orange)
        XCTAssertLessThan(HourTier.orange, .green)
    }
}

/// Spec 14 §3 pinned invariant: **the server's day rating is truth** — the
/// greenest run of the client tiers must coincide with the server's returned
/// window for that day; any disagreement is a client bug. Tie-tolerant
/// (feasibility I6): on equal-length runs the server returns the earliest, so
/// the client asserts the server window is exactly its tier throughout and
/// that NO LONGER run exists — not that it is the unique maximal run.
final class HourQualityInvariantTests: XCTestCase {

    /// The threshold profiles the fixture was captured with (2026-07-12 — the
    /// two #5a seed Templates, verified unchanged in git between #5a and the
    /// capture). Frozen WITH the fixture: re-tuning today's templates must not
    /// silently rewrite this invariant.
    private let capturedThresholds: [String: [String: Threshold]] = [
        "cycling": [
            "temp": Threshold(min: 15, max: 32, required: true),
            "windSpeed": Threshold(max: 25, required: false),
            "rainFall": Threshold(max: 0.2, required: true),
            "uV": Threshold(max: 8, required: false),
        ],
        "fishing-lite": [
            "temp": Threshold(min: 12, max: 36, required: true),
            "windSpeed": Threshold(max: 25, required: true),
            "cloudCover": Threshold(max: 80, required: false),
        ],
    ]

    func testGreenestRunCoincidesWithServerWindowOnEveryDay() throws {
        let forecast = try JSONDecoder().decode(ForecastResponse.self,
                                                from: Data(RealBackendResponse.json.utf8))
        let deriver = try XCTUnwrap(TimeDeriver(forecastStart: forecast.forecastStart,
                                                timezone: forecast.timezone))
        XCTAssertEqual(forecast.hours.count, RealBackendResponse.hourCount)

        for activity in forecast.activities {
            let thresholds = try XCTUnwrap(capturedThresholds[activity.activityId],
                                           "unexpected activity \(activity.activityId) in the fixture")
            let tiers = forecast.hours.map { HourQuality.tier(for: $0, thresholds: thresholds) }

            for day in activity.days {
                let bucket = try XCTUnwrap(deriver.hourRange(forDayIndex: day.dayIndex,
                                                             hourCount: forecast.hours.count),
                                           "\(activity.activityId) day \(day.dayIndex) must be inside the horizon")
                let bucketTiers = Array(tiers[bucket])
                let label = "\(activity.activityId) day \(day.dayIndex)"

                switch day.rating {
                case "perfect":
                    try assertWindowIsMaximalRun(day, bucket: bucket, bucketTiers: bucketTiers,
                                                 tier: .green, label: label)
                case "good":
                    XCTAssertFalse(bucketTiers.contains(.green),
                                   "\(label): a good day can hold no green hour — one green hour is a 1h perfect window server-side")
                    try assertWindowIsMaximalRun(day, bucket: bucket, bucketTiers: bucketTiers,
                                                 tier: .orange, label: label)
                default:
                    XCTAssertNil(day.rating, label)
                    XCTAssertFalse(bucketTiers.contains(.green),
                                   "\(label): a null day with a client-green hour is mirror drift")
                    XCTAssertFalse(bucketTiers.contains(.orange),
                                   "\(label): a null day with a client-orange hour is mirror drift")
                }
            }
        }
    }

    private func assertWindowIsMaximalRun(_ day: Day, bucket: Range<Int>, bucketTiers: [HourTier],
                                          tier expected: HourTier, label: String) throws {
        let start = try XCTUnwrap(day.startIndex, label)
        let end = try XCTUnwrap(day.endIndex, label)
        let duration = try XCTUnwrap(day.duration, label)
        XCTAssertEqual(duration, end - start, "\(label): duration is end − start")
        XCTAssertTrue(start >= bucket.lowerBound && end <= bucket.upperBound,
                      "\(label): global window indices sit inside the day bucket")

        for index in start..<end {
            XCTAssertEqual(bucketTiers[index - bucket.lowerBound], expected,
                           "\(label): hour \(index) inside the server window must be \(expected)")
        }
        XCTAssertLessThanOrEqual(longestRun(of: expected, in: bucketTiers), duration,
                                 "\(label): the client found a LONGER \(expected) run than the server window — mirror drift")
    }

    private func longestRun(of tier: HourTier, in tiers: [HourTier]) -> Int {
        var best = 0
        var current = 0
        for t in tiers {
            current = t == tier ? current + 1 : 0
            best = max(best, current)
        }
        return best
    }
}
