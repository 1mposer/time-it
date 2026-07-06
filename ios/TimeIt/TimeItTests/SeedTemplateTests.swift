import XCTest
@testable import TimeIt

/// Tripwire: a seed Template with an invalid body silently 400s the WHOLE dashboard
/// (validation is atomic server-side). Pins the ADR-0005 invariants on the shipped seeds.
final class SeedTemplateTests: XCTestCase {

    /// Live metrics per src/weather/metricCatalog.js — the only metrics a request may use.
    private let liveMetrics: Set<String> = [
        "temp", "humidity", "windSpeed", "rainFall", "cloudCover",
        "visibility", "uV", "moon", "dustAlert",
    ]

    func testShipsTwoSeedsInOrder() {
        XCTAssertEqual(SeedTemplates.all.map(\.id), ["cycling", "fishing-lite"])
        XCTAssertEqual(SeedTemplates.all.map(\.label), ["Cycling", "Fishing Lite"])
    }

    func testIdsAreUniqueWithinRequest() {
        let ids = SeedTemplates.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testOnlyLiveMetricsAnywhere() {
        for activity in SeedTemplates.all {
            for metric in activity.displayMetrics {
                XCTAssertTrue(liveMetrics.contains(metric),
                              "\(activity.id) displays coming-soon/unknown metric \(metric) — hard 400")
            }
            for metric in activity.thresholds.keys {
                XCTAssertTrue(liveMetrics.contains(metric),
                              "\(activity.id) thresholds coming-soon/unknown metric \(metric) — hard 400")
            }
        }
    }

    func testThresholdKeysAreSubsetOfDisplayMetrics() {
        for activity in SeedTemplates.all {
            XCTAssertTrue(Set(activity.thresholds.keys).isSubset(of: Set(activity.displayMetrics)),
                          "\(activity.id) violates thresholds.keys ⊆ displayMetrics")
        }
    }

    func testDisplayMetricsNonEmpty() {
        for activity in SeedTemplates.all {
            XCTAssertFalse(activity.displayMetrics.isEmpty)
            XCTAssertFalse(activity.label.isEmpty)
            XCTAssertFalse(activity.id.isEmpty)
        }
    }

    func testNumericThresholdsCarryAtLeastOneBound() {
        for activity in SeedTemplates.all {
            for (metric, threshold) in activity.thresholds {
                XCTAssertTrue(threshold.min != nil || threshold.max != nil,
                              "\(activity.id).\(metric) is bound-less — hard 400")
            }
        }
    }

    func testEncodedBodyMatchesADR0005() throws {
        let request = RatingRequest(lat: 25.1627, lon: 55.2077, activities: SeedTemplates.all)
        let data = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(body["lat"] as? Double, 25.1627)
        XCTAssertEqual(body["lon"] as? Double, 55.2077)

        let activities = try XCTUnwrap(body["activities"] as? [[String: Any]])
        XCTAssertEqual(activities.count, 2)

        for activity in activities {
            XCTAssertNil(activity["window"], "#5a seeds are diurnal — the window key must be omitted entirely")
            let thresholds = try XCTUnwrap(activity["thresholds"] as? [String: [String: Any]])
            for (metric, threshold) in thresholds {
                XCTAssertNotNil(threshold["required"], "\(metric) threshold is missing required — hard 400")
                XCTAssertTrue(threshold["required"] is Bool)
            }
        }
    }
}
