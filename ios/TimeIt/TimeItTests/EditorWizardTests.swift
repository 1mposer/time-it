import XCTest
@testable import TimeIt

/// Pins the wizard's per-tab completion rules (§1 of the redesign), the
/// forward-gating rule, the rangeConfirmed seeding, and the 3-way threshold
/// mode mapping (§4). Green = live validity — a tab's rule passing NOW, never
/// "visited".
final class EditorWizardTests: XCTestCase {

    private let catalog = StaticMetricCatalog()

    private func blankDraft() -> ActivityDraft {
        ActivityDraft(from: .blank())
    }

    private func descriptor(_ key: String) -> MetricDescriptor {
        catalog.descriptor(for: key)!
    }

    private func complete(_ step: EditorStep, _ draft: ActivityDraft,
                          rangeConfirmed: Bool = false) -> Bool {
        step.isComplete(draft: draft, catalog: catalog, rangeConfirmed: rangeConfirmed)
    }

    // MARK: tab 0 — name & icon

    func testNameIconGateNeedsBothANameAndANonSentinelIcon() {
        var draft = blankDraft()
        XCTAssertFalse(complete(.nameIcon, draft), "blank draft: no name, sentinel icon")

        draft.label = "Padel"
        XCTAssertFalse(complete(.nameIcon, draft), "the sentinel icon is not a chosen icon")

        draft.iconSymbol = "figure.tennis"
        XCTAssertTrue(complete(.nameIcon, draft))

        draft.label = "   "
        XCTAssertFalse(complete(.nameIcon, draft), "whitespace-only name is empty")
    }

    func testNameIconGateRevertsWhenTheNameIsCleared() {
        var draft = blankDraft()
        draft.label = "Padel"
        draft.iconSymbol = "figure.tennis"
        XCTAssertTrue(complete(.nameIcon, draft))
        draft.label = ""
        XCTAssertFalse(complete(.nameIcon, draft), "green is live validity, never visited")
    }

    // MARK: tab 1 — metrics

    func testMetricsGateNeedsAtLeastOneSelectedMetric() {
        XCTAssertFalse(complete(.metrics, blankDraft()))

        var draft = blankDraft()
        draft.selectWithPreset(descriptor("moon"))
        XCTAssertTrue(complete(.metrics, draft), "a show-only metric with no threshold completes the tab")
    }

    func testMetricsGateFailsWhileAThresholdDoesNotParse() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("temp"))
        XCTAssertTrue(complete(.metrics, draft), "the preset threshold parses out of the box")

        draft.thresholds["temp"]?.minText = "abc"
        XCTAssertFalse(complete(.metrics, draft), "a non-numeric bound is a threshold issue")

        draft.thresholds["temp"]?.minText = ""
        draft.thresholds["temp"]?.maxText = ""
        XCTAssertFalse(complete(.metrics, draft), "a bound-less numeric threshold is a threshold issue")
    }

    func testMetricsGateIgnoresIssuesNotAttributableToThresholds() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("temp"))
        // Name still empty and icon still the sentinel — tab 0's problem, not tab 1's.
        XCTAssertTrue(complete(.metrics, draft))
    }

    // MARK: tab 2 — range

    func testRangeGateNeedsDistinctHoursAndConfirmation() {
        var draft = blankDraft()
        draft.startHour = 6
        draft.endHour = 6
        XCTAssertFalse(complete(.range, draft, rangeConfirmed: true), "equal hours never complete")

        draft.endHour = 10
        XCTAssertFalse(complete(.range, draft, rangeConfirmed: false), "an unconfirmed prefill is not complete")
        XCTAssertTrue(complete(.range, draft, rangeConfirmed: true))
    }

    func testRangeConfirmedSeedsFromTheIncomingWindow() {
        XCTAssertTrue(ActivityDraft(from: SeedTemplates.cycling).hadWindow,
                      "a live activity arrives range-confirmed")
        XCTAssertFalse(ActivityDraft(from: .blank()).hadWindow,
                       "a from-scratch draft must confirm its range")

        var dormant = SeedTemplates.cycling
        dormant.window = nil
        XCTAssertFalse(ActivityDraft(from: dormant).hadWindow,
                       "a dormant showcase activity must confirm its prefill")
    }

    // MARK: tab 3 — review

    func testReviewGateIsTheBuildResult() {
        XCTAssertFalse(complete(.review, blankDraft()))
        XCTAssertTrue(complete(.review, ActivityDraft(from: SeedTemplates.cycling), rangeConfirmed: true))
    }

    // MARK: gating — tab i is tappable iff tabs 0..<i are all complete

    func testForwardGatingUnlocksTabsInOrder() {
        var draft = blankDraft()
        XCTAssertTrue(EditorStep.nameIcon.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))
        XCTAssertFalse(EditorStep.metrics.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))
        XCTAssertFalse(EditorStep.review.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))

        draft.label = "Padel"
        draft.iconSymbol = "figure.tennis"
        XCTAssertTrue(EditorStep.metrics.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))
        XCTAssertFalse(EditorStep.range.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false),
                       "no metric yet — the Range tab stays locked")

        draft.selectWithPreset(descriptor("temp"))
        XCTAssertTrue(EditorStep.range.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))
        XCTAssertFalse(EditorStep.review.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false),
                       "the range is valid but unconfirmed — Review stays locked")
    }

    func testEditModeUnlocksEverythingImmediately() {
        let draft = ActivityDraft(from: SeedTemplates.cycling)
        for step in EditorStep.allCases {
            XCTAssertTrue(step.isComplete(draft: draft, catalog: catalog, rangeConfirmed: draft.hadWindow),
                          "\(step) must pass for a previously saved activity")
            XCTAssertTrue(step.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: draft.hadWindow))
        }
    }

    // MARK: selection with preset (§4 — one tap = a working Must-have threshold)

    func testSelectWithPresetCreatesAPresetThreshold() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("temp"))
        XCTAssertEqual(draft.metrics, ["temp"])
        XCTAssertEqual(draft.thresholds["temp"], ThresholdDraft(preset: descriptor("temp")))
    }

    func testSelectWithPresetOnADisplayOnlyMetricAddsNoThreshold() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("moon"))
        XCTAssertEqual(draft.metrics, ["moon"])
        XCTAssertNil(draft.thresholds["moon"])
    }

    func testSelectWithPresetIsANoOpOnAnAlreadySelectedMetric() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        let before = draft
        draft.selectWithPreset(descriptor("temp"))
        XCTAssertEqual(draft, before, "re-selecting must not clobber authored threshold values")
    }

    // MARK: threshold mode mapping (§4)

    func testCurrentModeReflectsTheDraftState() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        XCTAssertEqual(ThresholdMode.current(for: "temp", in: draft), .mustHave)
        XCTAssertEqual(ThresholdMode.current(for: "windSpeed", in: draft), .niceToHave)
        draft.removeThreshold(for: "temp")
        XCTAssertEqual(ThresholdMode.current(for: "temp", in: draft), .showOnly)
    }

    func testApplyModeTogglesRequiredWithoutTouchingValues() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        draft.thresholds["temp"]?.minText = "18"

        ThresholdMode.niceToHave.apply(for: descriptor("temp"), to: &draft)
        XCTAssertEqual(draft.thresholds["temp"]?.required, false)
        XCTAssertEqual(draft.thresholds["temp"]?.minText, "18", "authored values survive a mode flip")

        ThresholdMode.mustHave.apply(for: descriptor("temp"), to: &draft)
        XCTAssertEqual(draft.thresholds["temp"]?.required, true)
        XCTAssertEqual(draft.thresholds["temp"]?.minText, "18")
    }

    func testApplyShowOnlyRemovesTheThresholdButKeepsTheMetric() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        ThresholdMode.showOnly.apply(for: descriptor("temp"), to: &draft)
        XCTAssertNil(draft.thresholds["temp"])
        XCTAssertTrue(draft.isSelected("temp"), "show only: on the card, doesn't affect rating")
    }

    func testApplyAThresholdModeAfterShowOnlyRecreatesThePreset() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        ThresholdMode.showOnly.apply(for: descriptor("temp"), to: &draft)
        ThresholdMode.mustHave.apply(for: descriptor("temp"), to: &draft)
        XCTAssertEqual(draft.thresholds["temp"], ThresholdDraft(preset: descriptor("temp")))
    }

    func testFlagMetricModesMapToTheFlagThreshold() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("dustAlert"))
        XCTAssertEqual(draft.thresholds["dustAlert"]?.isFlag, true)
        XCTAssertEqual(ThresholdMode.current(for: "dustAlert", in: draft), .mustHave)

        ThresholdMode.niceToHave.apply(for: descriptor("dustAlert"), to: &draft)
        XCTAssertEqual(draft.thresholds["dustAlert"]?.required, false)
        XCTAssertEqual(draft.thresholds["dustAlert"]?.isFlag, true)

        ThresholdMode.showOnly.apply(for: descriptor("dustAlert"), to: &draft)
        XCTAssertNil(draft.thresholds["dustAlert"])
    }

    func testModeLabelsAreTheSettledCopy() {
        XCTAssertEqual(ThresholdMode.mustHave.label, "Must-have")
        XCTAssertEqual(ThresholdMode.niceToHave.label, "Nice-to-have")
        XCTAssertEqual(ThresholdMode.showOnly.label, "Show only")
    }

    // MARK: two-checkbox surface (owner edit 2026-08-30 — replaces the mode menu)

    func testCheckboxStateReflectsTheDraft() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        XCTAssertTrue(ThresholdCheckboxes.isPriority(for: "temp", in: draft),
                      "a required threshold reads as Priority checked")
        XCTAssertFalse(ThresholdCheckboxes.isShowOnly(for: "temp", in: draft))

        XCTAssertFalse(ThresholdCheckboxes.isPriority(for: "windSpeed", in: draft),
                       "an optional threshold is calculating but not Priority")
        XCTAssertFalse(ThresholdCheckboxes.isShowOnly(for: "windSpeed", in: draft))

        draft.removeThreshold(for: "temp")
        XCTAssertFalse(ThresholdCheckboxes.isPriority(for: "temp", in: draft))
        XCTAssertTrue(ThresholdCheckboxes.isShowOnly(for: "temp", in: draft),
                      "no threshold on a selected metric = show don't calculate")
    }

    func testTogglingPriorityFlipsRequiredWithoutTouchingValues() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        draft.thresholds["temp"]?.minText = "18"

        ThresholdCheckboxes.togglePriority(for: descriptor("temp"), in: &draft)
        XCTAssertEqual(draft.thresholds["temp"]?.required, false,
                       "unchecking Priority keeps calculating, just softer")
        XCTAssertEqual(draft.thresholds["temp"]?.minText, "18", "authored values survive")

        ThresholdCheckboxes.togglePriority(for: descriptor("temp"), in: &draft)
        XCTAssertEqual(draft.thresholds["temp"]?.required, true)
        XCTAssertEqual(draft.thresholds["temp"]?.minText, "18")
    }

    func testCheckingShowOnlyRemovesTheThresholdAndUnchecksPriority() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        ThresholdCheckboxes.toggleShowOnly(for: descriptor("temp"), in: &draft)
        XCTAssertNil(draft.thresholds["temp"], "show don't calculate drops the threshold")
        XCTAssertTrue(draft.isSelected("temp"), "the metric stays on the card")
        XCTAssertFalse(ThresholdCheckboxes.isPriority(for: "temp", in: draft),
                       "the two boxes can never both read checked")
    }

    func testUncheckingShowOnlyRecreatesThePresetAsPriority() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        ThresholdCheckboxes.toggleShowOnly(for: descriptor("temp"), in: &draft)
        ThresholdCheckboxes.toggleShowOnly(for: descriptor("temp"), in: &draft)
        XCTAssertEqual(draft.thresholds["temp"], ThresholdDraft(preset: descriptor("temp")),
                       "back to calculating = the preset Must-have threshold")
        XCTAssertTrue(ThresholdCheckboxes.isPriority(for: "temp", in: draft))
    }

    func testCheckingPriorityFromShowOnlyRecreatesThePreset() {
        var draft = ActivityDraft(from: SeedTemplates.cycling)
        ThresholdCheckboxes.toggleShowOnly(for: descriptor("temp"), in: &draft)
        ThresholdCheckboxes.togglePriority(for: descriptor("temp"), in: &draft)
        XCTAssertEqual(draft.thresholds["temp"], ThresholdDraft(preset: descriptor("temp")),
                       "checking Priority while show-only re-creates the threshold and unchecks the show box")
        XCTAssertFalse(ThresholdCheckboxes.isShowOnly(for: "temp", in: draft))
    }
}
