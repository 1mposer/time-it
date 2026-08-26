import XCTest
@testable import TimeIt

/// Client-side static metric catalog: a hand-maintained mirror of the backend
/// LIVE set behind the MetricCatalogProviding swap seam — the drift tripwire
/// until GET /api/v1/metrics lands (its ADR is unwritten; 0006 is the push ADR).
final class MetricCatalogTests: XCTestCase {

    /// LIVE_METRICS in src/weather/metricCatalog.js — mirror exactly.
    private let backendLiveSet: Set<String> = [
        "temp", "humidity", "windSpeed", "rainFall", "cloudCover",
        "visibility", "uV", "moon", "dustAlert",
    ]

    private let comingSoonSet: Set<String> = [
        "darkness", "douglasScale", "swellHeight", "swellLength", "tide", "seaWarning",
    ]

    private let catalog = StaticMetricCatalog()

    func testCatalogKeysAreExactlyTheBackendLiveSet() {
        XCTAssertEqual(Set(catalog.metrics.map(\.key)), backendLiveSet,
                       "drift tripwire — must mirror LIVE_METRICS in src/weather/metricCatalog.js")
        XCTAssertEqual(catalog.metrics.count, 9, "no duplicate keys")
    }

    func testNoComingSoonKeyIsOffered() {
        for descriptor in catalog.metrics {
            XCTAssertFalse(comingSoonSet.contains(descriptor.key),
                           "\(descriptor.key) is coming-soon — offering it guarantees an atomic 400")
        }
    }

    func testEveryEntryHasAManifestIconAndDisplayName() {
        let manifestIcons: [String: String] = [
            "temp": "thermometer.medium",
            "windSpeed": "wind",
            "rainFall": "cloud.rain.fill",
            "uV": "sun.max.fill",
            "cloudCover": "cloud.fill",
            "humidity": "humidity.fill",
            "visibility": "eye.fill",
            "moon": "moon.stars.fill",
            "dustAlert": "sun.dust.fill",
        ]
        for descriptor in catalog.metrics {
            XCTAssertEqual(descriptor.iconSymbol, manifestIcons[descriptor.key],
                           "\(descriptor.key) icon must come from the manifest")
            XCTAssertFalse(descriptor.displayName.isEmpty)
        }
    }

    func testKindsMatchTheContract() {
        func kind(_ key: String) -> MetricKind? {
            catalog.metrics.first { $0.key == key }?.kind
        }
        XCTAssertEqual(kind("dustAlert"), .flag, "dustAlert is the one LIVE flag metric")
        XCTAssertEqual(kind("moon"), .displayOnly, "moon is display-only in #5b — no threshold UI")
        for key in ["temp", "humidity", "windSpeed", "rainFall", "cloudCover", "visibility", "uV"] {
            XCTAssertEqual(kind(key), .numeric, "\(key) takes min/max bounds")
        }
    }

    func testNoMetricIsProToday() {
        for descriptor in catalog.metrics {
            XCTAssertFalse(descriptor.pro, "\(descriptor.key): no LIVE metric is Pro-gated (Pro deferred, §8)")
        }
    }

    func testNumericMetricsCarryEditorRanges() {
        for descriptor in catalog.metrics where descriptor.kind == .numeric {
            XCTAssertNotNil(descriptor.range, "\(descriptor.key) needs slider/stepper bounds for the editor")
        }
    }

    func testThresholdabilityFollowsKind() {
        for descriptor in catalog.metrics {
            XCTAssertEqual(descriptor.isThresholdable, descriptor.kind != .displayOnly)
        }
    }
}
