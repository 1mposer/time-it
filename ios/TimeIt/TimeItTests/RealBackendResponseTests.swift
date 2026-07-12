import XCTest
@testable import TimeIt

/// Regression net against a REAL captured backend response (see
/// `RealBackendResponseFixture.swift`). The synthetic fixtures decode a shape
/// *I* hand-wrote; this decodes the shape the provider actually emits, at real
/// scale (166 hours) and spanning 118 night hours — the conditions that blanked
/// the dashboard before the uV-null fix. If the decoder or the wire contract
/// ever drifts from reality, this fails where the daytime-only mocks stayed green.
final class RealBackendResponseTests: XCTestCase {

    private func decode(_ json: String = RealBackendResponse.json) throws -> ForecastResponse {
        try JSONDecoder().decode(ForecastResponse.self, from: Data(json.utf8))
    }

    /// The whole point: a real, full-scale, night-spanning response decodes
    /// end-to-end. Pre-fix, this exact payload threw on the first night hour
    /// (`uV: null`) and failed the *entire* decode on every real request.
    func testRealBackendResponseDecodesFully() throws {
        let f = try decode()
        XCTAssertEqual(f.hours.count, RealBackendResponse.hourCount,
                       "must decode every real hour — not a hardcoded 7/24/168")
        XCTAssertEqual(f.hours.last?.index, f.hours.count - 1, "hours stay 0-based and contiguous")
        XCTAssertEqual(f.activities.count, 2)
        XCTAssertTrue(f.forecastStart.hasSuffix("Z"), "forecastStart must be UTC-Z for ISO8601 decode")
        XCTAssertEqual(f.timezone, "Asia/Dubai")
        // days.length is provider-driven (8 here, not 7) and per-activity — never hardcoded.
        XCTAssertTrue(f.activities.allSatisfy { !$0.days.isEmpty })
    }

    /// The response genuinely spans night — the trigger for the original bug.
    /// Night hours (`uV == 0` after dark) must be present *and* fully decoded.
    func testRealResponseSpansNightAndDecodesThoseHours() throws {
        let f = try decode()
        let nightHours = f.hours.filter { $0.uV == 0 }
        XCTAssertGreaterThan(nightHours.count, 24, "a 7-day forecast must span multiple nights")
        // Night didn't break decoding: those hours still carry their other metrics.
        XCTAssertTrue(nightHours.allSatisfy { $0.temp != nil })
    }

    /// Defence-in-depth: the backend now sends `uV: 0` (never null), but if that
    /// default is ever removed a null on ANY metric must render "—", not fail the
    /// whole decode. Inject nulls into hour 0 of the REAL payload and prove the
    /// full 166-hour response still decodes.
    func testRealResponseSurvivesInjectedNullMetrics() throws {
        var json = RealBackendResponse.json
        for key in ["uV", "windSpeed", "rainFall", "cloudCover"] {
            json = nullingFirstValue(of: key, in: json)
        }
        let f = try decode(json)
        XCTAssertEqual(f.hours.count, RealBackendResponse.hourCount, "an injected null must not abort the decode")
        XCTAssertNil(f.hours[0].uV)
        XCTAssertEqual(f.hours[0].formatted(for: "uV"), "—")
        XCTAssertNil(f.hours[0].windSpeed)
        // A later, untouched hour still carries its real value.
        XCTAssertNotNil(f.hours[1].uV)
    }

    /// Replace the first `"key":<value>` with `"key":null`. In the compact
    /// response the first such match is hour 0 (metric keys appear as bare array
    /// elements — no colon — inside displayMetrics, so they don't match).
    private func nullingFirstValue(of key: String, in json: String) -> String {
        guard let keyRange = json.range(of: "\"\(key)\":") else { return json }
        let valueStart = keyRange.upperBound
        guard let valueEnd = json[valueStart...].firstIndex(where: { $0 == "," || $0 == "}" }) else { return json }
        var mutated = json
        mutated.replaceSubrange(valueStart..<valueEnd, with: "null")
        return mutated
    }
}
