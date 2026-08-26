import XCTest
@testable import TimeIt

/// Regression net against a REAL captured backend response (see
/// `RealBackendResponseFixture.swift`): decodes the shape the provider
/// actually emits, at real scale (166 hours, 118 night) — the conditions
/// that blanked the dashboard before the uV-null fix. Catches decoder/wire
/// drift that daytime-only mocks would miss.
final class RealBackendResponseTests: XCTestCase {

    private func decode(_ json: String = RealBackendResponse.json) throws -> ForecastResponse {
        try JSONDecoder().decode(ForecastResponse.self, from: Data(json.utf8))
    }

    /// Pre-fix, this exact payload threw on the first night hour (`uV: null`)
    /// and failed the entire decode on every real request.
    func testRealBackendResponseDecodesFully() throws {
        let f = try decode()
        XCTAssertEqual(f.hours.count, RealBackendResponse.hourCount,
                       "must decode every real hour — not a hardcoded 7/24/168")
        XCTAssertEqual(f.hours.last?.index, f.hours.count - 1, "hours stay 0-based and contiguous")
        XCTAssertEqual(f.activities.count, 2)
        XCTAssertTrue(f.forecastStart.hasSuffix("Z"), "forecastStart must be UTC-Z for ISO8601 decode")
        XCTAssertEqual(f.timezone, "Asia/Dubai")
        // days.length is provider-driven (8, not 7) and per-activity — never hardcoded.
        XCTAssertTrue(f.activities.allSatisfy { !$0.days.isEmpty })
    }

    /// Night hours (`uV == 0` after dark) — the trigger for the uV-null bug —
    /// must be present and fully decoded.
    func testRealResponseSpansNightAndDecodesThoseHours() throws {
        let f = try decode()
        let nightHours = f.hours.filter { $0.uV == 0 }
        XCTAssertGreaterThan(nightHours.count, 24, "a 7-day forecast must span multiple nights")
        // Night hours still decode their other metrics correctly.
        XCTAssertTrue(nightHours.allSatisfy { $0.temp != nil })
    }

    /// Defence-in-depth: backend now sends `uV: 0` (never null), but if that
    /// default is removed, a null on ANY metric must render "—", not fail the
    /// whole decode. Inject nulls into hour 0 and prove the full decode survives.
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

    /// Replaces the first `"key":<value>` with `"key":null`. In the compact
    /// response the first match is hour 0 — metric names inside displayMetrics
    /// arrays have no colon, so they don't match.
    private func nullingFirstValue(of key: String, in json: String) -> String {
        guard let keyRange = json.range(of: "\"\(key)\":") else { return json }
        let valueStart = keyRange.upperBound
        guard let valueEnd = json[valueStart...].firstIndex(where: { $0 == "," || $0 == "}" }) else { return json }
        var mutated = json
        mutated.replaceSubrange(valueStart..<valueEnd, with: "null")
        return mutated
    }
}
