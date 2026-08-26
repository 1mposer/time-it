import XCTest
@testable import TimeIt

/// Pins the client-side mirror of the server's ADR-0005 validation — one bad
/// Activity 400s the whole request, so the editor must block invalid saves.
final class ActivityValidationTests: XCTestCase {

    private func makeValid() -> AuthoredActivity {
        AuthoredActivity(id: "a1",
                         label: "Padel",
                         iconSymbol: "questionmark.circle",
                         templateOrigin: nil,
                         displayMetrics: ["temp", "windSpeed"],
                         thresholds: ["temp": Threshold(min: 15, max: 35, required: true)],
                         window: nil)
    }

    func testValidActivityHasNoIssues() {
        XCTAssertTrue(makeValid().isValid)
        XCTAssertTrue(makeValid().validationIssues.isEmpty)
    }

    // MARK: label / metrics

    func testEmptyLabelIsInvalid() {
        var activity = makeValid()
        activity.label = ""
        XCTAssertFalse(activity.isValid)

        activity.label = "   "
        XCTAssertFalse(activity.isValid, "whitespace-only label is empty")
    }

    func testEmptyDisplayMetricsIsInvalid() {
        var activity = makeValid()
        activity.displayMetrics = []
        activity.thresholds = [:]
        XCTAssertFalse(activity.isValid)
    }

    func testComingSoonOrUnknownMetricIsInvalid() {
        var activity = makeValid()
        activity.displayMetrics = ["temp", "darkness"]
        XCTAssertFalse(activity.isValid)

        var unknown = makeValid()
        unknown.displayMetrics = ["temp", "sharknado"]
        XCTAssertFalse(unknown.isValid)
    }

    func testThresholdOnUndisplayedMetricIsInvalid() {
        var activity = makeValid()
        activity.thresholds["humidity"] = Threshold(max: 70, required: false)
        XCTAssertFalse(activity.isValid, "thresholds.keys ⊆ displayMetrics is the subset invariant")
    }

    // MARK: numeric thresholds

    func testBoundlessNumericThresholdIsInvalid() {
        var activity = makeValid()
        activity.thresholds["temp"] = Threshold(required: true)
        XCTAssertFalse(activity.isValid)
    }

    func testMinGreaterThanMaxIsInvalid() {
        var activity = makeValid()
        activity.thresholds["temp"] = Threshold(min: 35, max: 15, required: true)
        XCTAssertFalse(activity.isValid)
    }

    func testEqualBoundsAreValid() {
        var activity = makeValid()
        activity.thresholds["temp"] = Threshold(min: 20, max: 20, required: true)
        XCTAssertTrue(activity.isValid)
    }

    func testNonFiniteBoundsAreInvalid() {
        var activity = makeValid()
        activity.thresholds["temp"] = Threshold(max: .infinity, required: true)
        XCTAssertFalse(activity.isValid)

        activity.thresholds["temp"] = Threshold(min: .nan, max: 15, required: true)
        XCTAssertFalse(activity.isValid, "NaN sails past the min>max check — it must be caught explicitly")
    }

    func testDraftRejectsNonFiniteTextAndSurvivesHugeBounds() {
        var draft = ActivityDraft(from: makeValid())
        draft.thresholds["temp"] = {
            var t = ThresholdDraft()
            t.minText = "inf"
            return t
        }()
        XCTAssertNil(draft.result(against: StaticMetricCatalog()).activity)

        var activity = makeValid()
        activity.thresholds["temp"] = Threshold(max: 1e30, required: true)
        let reopened = ActivityDraft(from: activity)
        XCTAssertEqual(reopened.thresholds["temp"]?.maxText, "1e+30", "formats without trapping")
        XCTAssertNotNil(reopened.result(against: StaticMetricCatalog()).activity, "and round-trips")
    }

    func testThresholdOnDisplayOnlyMetricIsInvalidEvenAsFlag() {
        var activity = makeValid()
        activity.displayMetrics = ["temp", "windSpeed", "moon"]
        activity.thresholds["moon"] = Threshold(required: true, type: "flag", forbidTrue: true)
        XCTAssertFalse(activity.isValid)
    }

    // MARK: threshold shape must match the metric's kind (false-Perfect guard)

    func testFlagThresholdOnNumericMetricIsInvalid() {
        var activity = makeValid()
        activity.thresholds["temp"] = Threshold(required: true, type: "flag", forbidTrue: true)
        XCTAssertFalse(activity.isValid)
    }

    func testNumericThresholdOnFlagMetricIsInvalid() {
        var activity = makeValid()
        activity.displayMetrics = ["temp", "windSpeed", "dustAlert"]
        activity.thresholds["dustAlert"] = Threshold(min: 0, max: 1, required: true)
        XCTAssertFalse(activity.isValid, "dustAlert is a flag — min/max bounds are the wrong shape")
    }

    // MARK: flag thresholds

    func testFlagThresholdShapeNeverEmitsRequireTrue() throws {
        let flag = Threshold(required: true, type: "flag", forbidTrue: true)
        let data = try JSONEncoder().encode(flag)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(json.keys), ["type", "forbidTrue", "required"],
                       "flag threshold is exactly { type, forbidTrue, required } — requireTrue is rejected server-side (Issue #8)")
        XCTAssertEqual(json["type"] as? String, "flag")
        XCTAssertEqual(json["forbidTrue"] as? Bool, true)
    }

    func testFlagThresholdWithoutForbidTrueIsInvalid() {
        var activity = makeValid()
        activity.displayMetrics = ["temp", "windSpeed", "dustAlert"]
        activity.thresholds["dustAlert"] = Threshold(required: true, type: "flag", forbidTrue: nil)
        XCTAssertFalse(activity.isValid, "a flag threshold must set forbidTrue: true")

        activity.thresholds["dustAlert"] = Threshold(required: true, type: "flag", forbidTrue: true)
        XCTAssertTrue(activity.isValid)
    }

    // MARK: window

    func testBlankDraftDefaultsToTheFromScratchPrefillRange() {
        let draft = ActivityDraft(from: .blank())
        XCTAssertEqual(draft.startHour, 6)
        XCTAssertEqual(draft.endHour, 10)
    }

    func testDraftAlwaysBuildsARangedActivity() {
        let built = ActivityDraft(from: SeedTemplates.firstLaunchSeeds[0])
            .result(against: StaticMetricCatalog()).activity
        XCTAssertEqual(built?.window, WindowSpec(startHour: 6, endHour: 10),
                       "saving confirms the prefilled range — never a window-less body")
    }

    func testDormantShowcaseSeedDraftsAtItsTemplatePrefillRange() {
        for (seed, template) in zip(SeedTemplates.firstLaunchSeeds, SeedTemplates.all) {
            let draft = ActivityDraft(from: seed)
            XCTAssertEqual(draft.startHour, template.window?.startHour,
                           "\(seed.id) must prefill its template's startHour")
            XCTAssertEqual(draft.endHour, template.window?.endHour,
                           "\(seed.id) must prefill its template's endHour")
        }
    }

    func testDormantTemplateCopyDraftsAtItsOriginsPrefillRange() {
        var copy = SeedTemplates.stargazing.copyFromTemplate()
        copy.window = nil
        let draft = ActivityDraft(from: copy)
        XCTAssertEqual(draft.startHour, 22)
        XCTAssertEqual(draft.endHour, 4)
    }

    func testWindowWithEqualHoursIsInvalid() {
        var activity = makeValid()
        activity.window = WindowSpec(startHour: 8, endHour: 8)
        XCTAssertFalse(activity.isValid, "startHour === endHour is rejected (empty half-open window)")
        XCTAssertFalse(activity.validationIssues.joined().contains("whole-day"),
                       "spec 14 §1: whole-day activities no longer exist — the copy must stop offering the window-off fix")
    }

    func testWrappedWindowIsValid() {
        var activity = makeValid()
        activity.window = WindowSpec(startHour: 22, endHour: 2)
        XCTAssertTrue(activity.isValid, "wrap = nocturnal, a legal window")
    }

    func testOutOfRangeWindowHourIsInvalid() {
        var activity = makeValid()
        activity.window = WindowSpec(startHour: 24, endHour: 2)
        XCTAssertFalse(activity.isValid)

        activity.window = WindowSpec(startHour: 22, endHour: -1)
        XCTAssertFalse(activity.isValid)
    }

    // MARK: catalog seam

    func testValidationUsesTheInjectedCatalog() {
        struct FakeCatalog: MetricCatalogProviding {
            let metrics = [MetricDescriptor(key: "fakeMetric",
                                            displayName: "Fake",
                                            unit: "",
                                            iconSymbol: "questionmark.circle",
                                            kind: .numeric,
                                            pro: false,
                                            range: nil)]
        }
        var activity = makeValid()
        activity.displayMetrics = ["fakeMetric"]
        activity.thresholds = ["fakeMetric": Threshold(max: 5, required: true)]

        XCTAssertFalse(activity.validationIssues(against: StaticMetricCatalog()).isEmpty,
                       "fakeMetric is not LIVE in the real catalog")
        XCTAssertTrue(activity.validationIssues(against: FakeCatalog()).isEmpty,
                      "consumers depend on MetricCatalogProviding — the swap seam works")
    }
}
