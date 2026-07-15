import XCTest
@testable import TimeIt

/// Tripwire: a Template with an invalid body silently 400s the WHOLE dashboard
/// (validation is atomic server-side). Pins the ADR-0005 invariants on the
/// Template catalog (#5b §4.1) — every curated starting point must be a valid
/// body, because a template copy is saved (and POSTed) with minimal edits.
final class SeedTemplateTests: XCTestCase {

    /// Live metrics per src/weather/metricCatalog.js — the only metrics a request may use.
    private let liveMetrics: Set<String> = [
        "temp", "humidity", "windSpeed", "rainFall", "cloudCover",
        "visibility", "uV", "moon", "dustAlert",
    ]

    func testTemplateCatalogShipsInOrder() {
        XCTAssertEqual(SeedTemplates.all.map(\.id), ["cycling", "fishing-lite", "running", "stargazing"])
        XCTAssertEqual(SeedTemplates.all.map(\.label), ["Cycling", "Fishing Lite", "Running", "Stargazing"])
    }

    func testFirstLaunchSeedsAreTheTwo5aTemplates() {
        XCTAssertEqual(SeedTemplates.firstLaunchSeeds.map(\.id), ["cycling", "fishing-lite"],
                       "first launch must match the #5a dashboard exactly")
    }

    func testIdsAreUniqueWithinCatalog() {
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

    func testDisplayMetricsLabelIdAndIconNonEmpty() {
        for activity in SeedTemplates.all {
            XCTAssertFalse(activity.displayMetrics.isEmpty)
            XCTAssertFalse(activity.label.isEmpty)
            XCTAssertFalse(activity.id.isEmpty)
            XCTAssertFalse(activity.iconSymbol.isEmpty, "\(activity.id) needs a manifest icon (#5b §2)")
        }
    }

    func testNumericThresholdsCarryAtLeastOneBound() {
        for activity in SeedTemplates.all {
            for (metric, threshold) in activity.thresholds where threshold.type == nil {
                XCTAssertTrue(threshold.min != nil || threshold.max != nil,
                              "\(activity.id).\(metric) is bound-less — hard 400")
            }
        }
    }

    func testEveryTemplateIsAValidADR0005Body() {
        for activity in SeedTemplates.all {
            XCTAssertTrue(activity.isValid,
                          "\(activity.id) fails client validation: \(activity.validationIssues)")
        }
    }

    func testNocturnalTemplateHasAValidWrapWindow() {
        let stargazing = SeedTemplates.all.first { $0.id == "stargazing" }
        let window = stargazing?.window

        XCTAssertNotNil(window, "the catalog needs a nocturnal Template to exercise the night-stitch")
        XCTAssertGreaterThan(window?.startHour ?? 0, window?.endHour ?? 0, "wrap = startHour > endHour")
        XCTAssertEqual(stargazing?.isNocturnal, true)
    }

    func testEncodedBodyMatchesADR0005() throws {
        let request = RatingRequest(lat: 25.1627, lon: 55.2077,
                                    activities: SeedTemplates.all.map(\.activityInput))
        let data = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(body["lat"] as? Double, 25.1627)
        XCTAssertEqual(body["lon"] as? Double, 55.2077)

        let activities = try XCTUnwrap(body["activities"] as? [[String: Any]])
        XCTAssertEqual(activities.count, 4)

        for activity in activities {
            let thresholds = try XCTUnwrap(activity["thresholds"] as? [String: [String: Any]])
            for (metric, threshold) in thresholds {
                XCTAssertNotNil(threshold["required"], "\(metric) threshold is missing required — hard 400")
                XCTAssertTrue(threshold["required"] is Bool)
            }
            if activity["id"] as? String == "stargazing" {
                let window = try XCTUnwrap(activity["window"] as? [String: Any], "the nocturnal template sends its window")
                XCTAssertTrue((window["startHour"] as? Int ?? 0) > (window["endHour"] as? Int ?? 0))
            } else {
                XCTAssertNil(activity["window"], "diurnal templates omit the window key entirely")
            }
        }
    }

    func testEveryTemplateIconIsInTheActivityIconManifest() {
        // Drift tripwire: the editor's icon picker reads the manifest list, not
        // the Templates — a Template whose icon is missing from the manifest
        // would silently lose its icon the first time a user edits it.
        for template in SeedTemplates.all {
            XCTAssertTrue(ActivityIconView.activityIconManifest.contains(template.iconSymbol),
                          "\(template.id) uses \(template.iconSymbol), which is not in ActivityIconView.activityIconManifest — update the design-decisions manifest table first, then the list")
        }
    }
}
