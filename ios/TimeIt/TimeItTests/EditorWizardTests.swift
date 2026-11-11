import XCTest
@testable import TimeIt

/// Pins the five-step wizard (owner rulings 2026-11-11): per-step completion,
/// forward gating, the rangeConfirmed seeding, the Priority step over the
/// threshold contract (pressed = required, unpressed = optional, at least
/// one pressed), the retired show-only adoption, and the progress fraction.
/// Complete = live validity — a step's rule passing NOW, never "visited".
final class EditorWizardTests: XCTestCase {

    // MARK: - Helpers

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

    // MARK: - Tab 0 — name & icon

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

    // MARK: - Tab 1 — metrics

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

    // MARK: - Tab 2 — range

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
        XCTAssertTrue(ActivityDraft(from: Fixtures.cycling).hadWindow,
                      "a live activity arrives range-confirmed")
        XCTAssertFalse(ActivityDraft(from: .blank()).hadWindow,
                       "a from-scratch draft must confirm its range")

        var dormant = Fixtures.cycling
        dormant.window = nil
        XCTAssertFalse(ActivityDraft(from: dormant).hadWindow,
                       "a dormant showcase activity must confirm its prefill")
    }

    // MARK: - Tab 3 — review

    func testReviewGateIsTheBuildResult() {
        XCTAssertFalse(complete(.review, blankDraft()))
        XCTAssertTrue(complete(.review, ActivityDraft(from: Fixtures.cycling), rangeConfirmed: true))
    }

    // MARK: - Gating chain — tab i is tappable iff tabs 0..<i are all complete

    func testForwardGatingUnlocksStepsInOrder() {
        var draft = blankDraft()
        XCTAssertTrue(EditorStep.nameIcon.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))
        XCTAssertFalse(EditorStep.metrics.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))
        XCTAssertFalse(EditorStep.review.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))

        draft.label = "Padel"
        draft.iconSymbol = "figure.tennis"
        XCTAssertTrue(EditorStep.metrics.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))
        XCTAssertFalse(EditorStep.priority.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false),
                       "no metric yet — Priority stays locked")

        draft.selectWithPreset(descriptor("temp"))
        XCTAssertTrue(EditorStep.priority.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))
        XCTAssertFalse(EditorStep.range.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false),
                       "nothing pressed on Priority — the Range step stays locked")

        PriorityChoice.toggle("temp", in: &draft)
        XCTAssertTrue(EditorStep.range.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false))
        XCTAssertFalse(EditorStep.review.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: false),
                       "the range is valid but unconfirmed — Review stays locked")
    }

    func testEditModeUnlocksEverythingImmediately() {
        let draft = ActivityDraft(from: Fixtures.cycling)
        for step in EditorStep.allCases {
            XCTAssertTrue(step.isComplete(draft: draft, catalog: catalog, rangeConfirmed: draft.hadWindow),
                          "\(step) must pass for a previously saved activity")
            XCTAssertTrue(step.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: draft.hadWindow))
        }
    }

    // MARK: - Landing step (#25 — the detail doors open their own tab)

    func testLandingHonoursTheRequestedTabForASavedActivity() {
        let draft = ActivityDraft(from: Fixtures.cycling)
        for requested in EditorStep.allCases {
            XCTAssertEqual(EditorStep.landingStep(requested: requested, draft: draft, catalog: catalog,
                                                  rangeConfirmed: draft.hadWindow),
                           requested, "a saved activity unlocks every tab, so Edit range/metrics land where asked")
        }
    }

    func testLandingFallsBackToTheHighestUnlockedTabAtOrBelowTheRequest() {
        var draft = blankDraft()
        XCTAssertEqual(EditorStep.landingStep(requested: .range, draft: draft, catalog: catalog, rangeConfirmed: false),
                       .nameIcon, "nothing is complete — only tab 0 is open")

        draft.label = "Padel"
        draft.iconSymbol = "figure.tennis"
        XCTAssertEqual(EditorStep.landingStep(requested: .range, draft: draft, catalog: catalog, rangeConfirmed: false),
                       .metrics, "Range is locked without a metric — land on Metrics, never on a gated step")
        XCTAssertEqual(EditorStep.landingStep(requested: .nameIcon, draft: draft, catalog: catalog, rangeConfirmed: false),
                       .nameIcon, "a request at or below the first locked tab is honoured as-is")
    }

    // MARK: - Preset selection (§4 — one tap = a working Must-have threshold)

    func testSelectWithPresetCreatesAPresetThresholdNotPrioritised() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("temp"))
        XCTAssertEqual(draft.metrics, ["temp"])
        var expected = ThresholdDraft(preset: descriptor("temp"))
        expected.required = false
        XCTAssertEqual(draft.thresholds["temp"], expected,
                       "a pick shows and is judged, but only the Priority step makes it required")
    }

    func testSelectWithPresetOnADisplayOnlyMetricAddsNoThreshold() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("moon"))
        XCTAssertEqual(draft.metrics, ["moon"])
        XCTAssertNil(draft.thresholds["moon"])
    }

    func testSelectWithPresetIsANoOpOnAnAlreadySelectedMetric() {
        var draft = ActivityDraft(from: Fixtures.cycling)
        let before = draft
        draft.selectWithPreset(descriptor("temp"))
        XCTAssertEqual(draft, before, "re-selecting must not clobber authored threshold values")
    }

    // MARK: - Priority step (owner rulings 2026-11-11)

    func testPriorityCandidatesAreThePickedJudgedMetricsInOrder() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("windSpeed"))
        draft.selectWithPreset(descriptor("moon"))
        draft.selectWithPreset(descriptor("temp"))
        draft.selectWithPreset(descriptor("dustAlert"))
        XCTAssertEqual(PriorityChoice.candidates(in: draft), ["windSpeed", "temp", "dustAlert"],
                       "Moon Phase can't be judged, so it never appears on Priority")
    }

    func testPressingFlipsRequiredWithoutTouchingTheBounds() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("temp"))
        draft.thresholds["temp"]?.minText = "18"
        XCTAssertFalse(PriorityChoice.isChosen("temp", in: draft))

        PriorityChoice.toggle("temp", in: &draft)
        XCTAssertTrue(PriorityChoice.isChosen("temp", in: draft))
        XCTAssertEqual(draft.thresholds["temp"]?.required, true)
        XCTAssertEqual(draft.thresholds["temp"]?.minText, "18", "bounds are never touched")

        PriorityChoice.toggle("temp", in: &draft)
        XCTAssertEqual(draft.thresholds["temp"]?.required, false)
    }

    func testPressingAFlagMetricMakesItsFlagRequired() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("dustAlert"))
        XCTAssertEqual(draft.thresholds["dustAlert"]?.isFlag, true)
        XCTAssertEqual(draft.thresholds["dustAlert"]?.required, false)
        PriorityChoice.toggle("dustAlert", in: &draft)
        XCTAssertEqual(draft.thresholds["dustAlert"]?.required, true)
    }

    func testTogglingAMetricWithoutAThresholdIsANoOp() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("moon"))
        let before = draft
        PriorityChoice.toggle("moon", in: &draft)
        XCTAssertEqual(draft, before)
    }

    func testPriorityGateNeedsAtLeastOnePressed() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("temp"))
        draft.selectWithPreset(descriptor("windSpeed"))
        XCTAssertFalse(complete(.priority, draft), "Press at least one: no required threshold means never red")
        PriorityChoice.toggle("windSpeed", in: &draft)
        XCTAssertTrue(complete(.priority, draft))
        XCTAssertEqual(PriorityChoice.gateHint, "Press at least one.")
    }

    func testPriorityGatePassesWhenNothingCanBeJudged() {
        var draft = blankDraft()
        draft.selectWithPreset(descriptor("moon"))
        XCTAssertTrue(complete(.priority, draft), "Moon Phase alone leaves nothing to press")
    }

    func testPriorityExplainerIsTheRuledCopy() {
        XCTAssertEqual(PriorityChoice.explainer, "Pressed ones matter most. The rest still show.")
    }

    // MARK: - Retired "Show only" (owner ruling 4a)

    func testOpeningAdoptsShowOnlyMetricsAsNotPrioritised() {
        var legacy = Fixtures.cycling
        legacy.thresholds["uV"] = nil          // a show-only numeric metric
        legacy.displayMetrics.append("moon")   // display-only stays untouched
        var draft = ActivityDraft(from: legacy)
        draft.adoptShowOnlyMetrics(catalog: catalog)

        XCTAssertEqual(draft.thresholds["uV"]?.required, false)
        XCTAssertEqual(draft.thresholds["uV"]?.maxText, ThresholdDraft(preset: descriptor("uV")).maxText,
                       "the preset bound, ready for the user to keep or move")
        XCTAssertNil(draft.thresholds["moon"])
        XCTAssertEqual(draft.thresholds["temp"]?.required, true, "existing thresholds are untouched")
    }

    // MARK: - Progress bar

    func testProgressNeverStartsAtZeroAndFillsOnReview() {
        let fractions = EditorStep.allCases.map(WizardProgress.fraction(for:))
        XCTAssertEqual(fractions.count, 5)
        for (actual, expected) in zip(fractions, [0.12, 0.34, 0.56, 0.78, 1.0]) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testStepHeadingsAreThePlainLanguageCopy() {
        XCTAssertEqual(EditorStep.nameIcon.heading, "Name your activity")
        XCTAssertEqual(EditorStep.metrics.heading, "Pick what to watch")
        XCTAssertEqual(EditorStep.priority.heading, "What matters most?")
        XCTAssertEqual(EditorStep.range.heading, "When do you go?")
        XCTAssertNil(EditorStep.review.heading)
        for heading in EditorStep.allCases.compactMap(\.heading) {
            XCTAssertFalse(heading.localizedCaseInsensitiveContains("range"), "no 'range' on screen")
            XCTAssertFalse(heading.localizedCaseInsensitiveContains("threshold"), "no 'threshold' on screen")
        }
    }

    // MARK: - Tile rows

    func testTileRowsPairAndGiveTheOpenedTileAFullRow() {
        XCTAssertEqual(MetricTile.rows(for: ["a", "b", "c"], opened: nil),
                       [.pair("a", "b"), .pair("c", nil)])
        XCTAssertEqual(MetricTile.rows(for: ["a", "b", "c", "d"], opened: "a"),
                       [.full("a"), .pair("b", "c"), .pair("d", nil)])
        XCTAssertEqual(MetricTile.rows(for: ["a", "b", "c"], opened: "b"),
                       [.pair("a", nil), .full("b"), .pair("c", nil)])
    }
}
