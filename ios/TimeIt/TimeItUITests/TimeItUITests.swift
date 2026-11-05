import XCTest

/// Acceptance tests for the dashboard and the authoring layer. The app is
/// launched with a hermetic mock backend (launch arguments below), so the
/// suite is deterministic — no Node server or Meteosource key needed.
/// - `UITEST_MOCK_SUCCESS`: canned ForecastResponse (first activity windowed
///   today, second windowed tomorrow, the rest null).
/// - `UITEST_MOCK_FAILURE`: the API throws providerUnavailable (server down / 502).
/// - `UITEST_RESET`: wipes persisted activities + preferences (incl. the
///   last-resolved cache and the dismissals keys) so each test starts
///   from first-launch state (omit to test persistence).
/// - `UITEST_SEED_LIVE`: pre-persists the two fixture activities as LIVE
///   (ranges confirmed) — the real first launch is an empty store (no
///   request, no cards), so card/flow tests scaffold on this instead.
/// - `UITEST_LOCATION`: mock location provider returns a fixed fix — without
///   it the provider never resolves and the app shows the no-location empty
///   state (the Dubai fallback is deleted).
/// - `UITEST_LOCATION_DENIED`: no fix and a `.denied` status — the "fresh
///   install, location denied" path.
/// - `UITEST_PUSH_DENY`: the mock notification authorizer denies instead of
///   granting — the push opt-in toggle must revert.
/// - `UITEST_BETA`: pins the beta gate ON (mock runs never read the
///   simulator's receipt) — the disclaimer banner + suggestion button render;
///   omitting it pins the gate OFF (the App Store face of the same archive).
/// - `UITEST_FEEDBACK_FAIL`: the mock feedback route throws a 500 — the
///   non-204 path must keep the typed text and offer retry.
/// - `UITEST_NOW=<ISO8601>`: pins the passed-hour clock. `launchApp` adds
///   `UITEST_NOW=2026-06-19T00:30:00Z` (4:30am Dubai, before every seeded
///   Range) unless the caller passes its own, so the pills and strips show
///   their live colours on the simulator instead of passed-grey.
/// - `UITEST_APPEARANCE=dark|light`: pins the colour scheme; absent = the
///   simulator's system appearance (the app no longer pins Light).
final class TimeItUITests: XCTestCase {

    // MARK: - Launch helpers

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 4:30am Dubai on the fixture's day 0 — before every seeded Range, so
    /// every run (whatever its other arguments) shows the live look.
    private static let pinnedNow = "UITEST_NOW=2026-06-19T00:30:00Z"

    private func launchApp(arguments: [String] = ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION"]) -> XCUIApplication {
        let app = XCUIApplication()
        // The clock pin rides along unless the caller pins its own instant.
        let pinsOwnClock = arguments.contains { $0.hasPrefix("UITEST_NOW=") }
        app.launchArguments = pinsOwnClock ? arguments : arguments + [Self.pinnedNow]
        app.launch()
        return app
    }

    /// The only edit door (owner ruling 2026-10-06 #2 — the card gear is
    /// gone): tap the card, then the detail's Edit metrics circle. Edit mode
    /// unlocks every wizard tab, so callers tab on from there.
    private func openEditorFromDetail(_ activityId: String, in app: XCUIApplication) {
        let card = app.buttons["card.\(activityId)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let editMetrics = app.buttons["detail.editMetrics"]
        XCTAssertTrue(editMetrics.waitForExistence(timeout: 5), "the detail's edit circles")
        editMetrics.tap()
        XCTAssertTrue(app.buttons["editor.tab.3"].waitForExistence(timeout: 5), "the editor sheet is up")
    }

    private func cardCount(in app: XCUIApplication) -> Int {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card.'")).count
    }

    /// SwiftUI Form rows are lazy — an offscreen row doesn't exist in the
    /// accessibility hierarchy until scrolled into view.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    // MARK: - Launch surface

    func testLaunchesDirectlyToDashboardWithNoGateOrTabBar() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["headerTime"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0, "no bottom tab bar (grill Q8)")
        XCTAssertFalse(app.buttons["Sign In"].exists)
        XCTAssertFalse(app.staticTexts["Sign In"].exists)
    }

    func testHeaderShowsCurrentConditionsAndGear() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION",
                                        "UITEST_APPEARANCE=light"])

        XCTAssertTrue(app.staticTexts["headerTime"].waitForExistence(timeout: 5))
        // Mock fixture's hours[0] = temp 24 / wind 10 / humidity 40 — header
        // renders from hours.first.
        XCTAssertTrue(app.staticTexts["10 km/h"].exists)
        XCTAssertTrue(app.staticTexts["40%"].exists)
        XCTAssertTrue(app.buttons["settingsGear"].exists, "top-right gear, not a sign-in button")
        assertHeaderNumeralSwap(app)
        attachScreenshot(app, named: "header-light")
    }

    /// Ruling 7: the temperature is the big numeral ("24°", no unit letter)
    /// and the clock leads the meta line — on the wind/humidity row, below
    /// the numeral.
    private func assertHeaderNumeralSwap(_ app: XCUIApplication,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let numeral = app.staticTexts["headerTemp"]
        let clock = app.staticTexts["headerTime"]
        let wind = app.staticTexts["10 km/h"]
        XCTAssertTrue(numeral.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(numeral.label, "24°", "the numeral is the mock's temperature", file: file, line: line)
        XCTAssertFalse(clock.label.isEmpty, file: file, line: line)
        XCTAssertLessThan(abs(clock.frame.midY - wind.frame.midY), 2,
                          "the clock sits on the meta line with wind", file: file, line: line)
        // midY, not maxY: the numeral's accessibility frame includes its
        // 130pt scrim, which extends past the meta line by design.
        XCTAssertGreaterThan(clock.frame.minY, numeral.frame.midY,
                             "the meta line is below the numeral", file: file, line: line)
        XCTAssertLessThan(clock.frame.maxX, wind.frame.minX, "the clock leads the meta line", file: file, line: line)
    }

    // MARK: - Cards

    func testOneCardPerActivityInRequestOrderWithNoProBadge() {
        let app = launchApp()

        let cycling = app.buttons["card.cycling"]
        let fishing = app.buttons["card.fishing-lite"]
        XCTAssertTrue(cycling.waitForExistence(timeout: 5))
        XCTAssertTrue(fishing.exists)
        XCTAssertTrue(app.staticTexts["Cycling"].exists)
        XCTAssertTrue(app.staticTexts["Fishing Lite"].exists)
        XCTAssertLessThan(cycling.frame.minY, fishing.frame.minY, "cards render in request order")
        XCTAssertFalse(app.staticTexts["PRO"].exists, "no PRO badge anywhere")
    }

    /// Card v2 — "Score ring" (approved frame `458:394`). The card is wordless
    /// beyond the name, the numerals and the colour: the score ring with its
    /// "Score" caption, an HOURS-ONLY blue Range chip, and the Range-scoped
    /// hour strip. The sublabel and the metric chips are not on the v2 frame.
    func testCardV2ShowsScoreRingHoursOnlyChipAndNoWords() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cycling"].exists)

        // Hours-only chip — the "Range · " prefix is dropped on the v2 card.
        XCTAssertTrue(app.staticTexts["rangeChip.cycling"].exists)
        XCTAssertEqual(app.staticTexts["rangeChip.cycling"].label, "6 – 10am",
                       "the v2 chip is hours-only — no \u{201C}Range \u{B7} \u{201D} prefix")
        XCTAssertTrue(app.staticTexts["rangeChip.fishing-lite"].exists,
                      "the null-verdict card keeps its range chip")

        // Still no rating word, and no sublabel/day name anywhere.
        XCTAssertFalse(app.staticTexts["Perfect"].exists)
        XCTAssertFalse(app.staticTexts["Good"].exists)
        XCTAssertFalse(app.staticTexts["Today \u{B7} 6\u{2013}10am"].exists,
                       "the v2 card drops the sublabel")
        XCTAssertFalse(app.staticTexts["Nothing in your range."].exists)
        XCTAssertFalse(app.staticTexts["Tomorrow"].exists,
                       "the dashboard never shows a later day — the week lives in the detail")

        // The ring's VoiceOver summary keeps the words the visual dropped,
        // and the mock's day 0 scores (Perfect 86 / null 31) reach it.
        XCTAssertEqual(app.otherElements["score.cycling"].label, "Perfect, score 86 out of 100",
                       "the ring draws the wire's day score")
        // A rating-null day with hours scores exactly 1 (every hour has a
        // required miss → 0, clamped to 1), so it still draws a NUMERAL ring,
        // not an empty one. The ring is empty only when `score` is null.
        XCTAssertEqual(app.otherElements["score.fishing-lite"].label, "No Window, score 1 out of 100",
                       "a rating-null day still carries a real score (ADR-0011)")

        // Spec 05: the week-dot row (shown by default) + the chevron.
        XCTAssertTrue(app.descendants(matching: .any)["weekDots.cycling"].exists,
                      "the card carries the week-dot row — shown is the natural state")
        XCTAssertTrue(app.buttons["cardChevron.cycling"].exists)
        XCTAssertEqual(app.buttons["cardChevron.cycling"].label, "Hide week")
        // Owner ruling 2026-10-06 #2: the card gear is gone — editing lives
        // only behind the detail's circles; the chevron sits alone top-right.
        XCTAssertFalse(app.buttons["gear.cycling"].exists, "no per-card gear")
        XCTAssertGreaterThan(app.buttons["cardChevron.cycling"].frame.midX,
                             app.buttons["card.cycling"].frame.midX,
                             "the chevron is the top-right element")
    }

    /// Spec 05 chevron ruling: tap hides the dot row, the choice is
    /// remembered per card across launches, tap again shows it.
    func testCardChevronHidesTheWeekAndIsRememberedAcrossRelaunch() {
        var app = launchApp()

        let chevron = app.buttons["cardChevron.cycling"]
        XCTAssertTrue(chevron.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["weekDots.cycling"].exists)
        let expandedHeight = app.buttons["card.cycling"].frame.height
        chevron.tap()
        XCTAssertFalse(app.descendants(matching: .any)["weekDots.cycling"].waitForExistence(timeout: 1),
                       "the chevron hides the dot row")
        XCTAssertEqual(app.buttons["cardChevron.cycling"].label, "Show week")
        XCTAssertLessThan(app.buttons["card.cycling"].frame.height, expandedHeight,
                          "a collapsed card is shorter — no empty space left behind")
        XCTAssertTrue(app.descendants(matching: .any)["weekDots.fishing-lite"].exists,
                      "per card — the other card keeps its dots")

        // Relaunch WITHOUT UITEST_RESET — remembered.
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_SEED_LIVE", "UITEST_LOCATION"])
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["weekDots.cycling"].exists,
                       "the collapse survives relaunch")
        XCTAssertTrue(app.descendants(matching: .any)["weekDots.fishing-lite"].exists)

        app.buttons["cardChevron.cycling"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["weekDots.cycling"].waitForExistence(timeout: 2),
                      "tap again → the dots are back")
    }

    // MARK: - Navigation

    func testTappingCardOpensDetailAndBackReturns() {
        let app = launchApp()

        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5), "detail uses the activity label as title")

        app.navigationBars["Cycling"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5), "back returns to the dashboard")
    }

    func testGearOpensSettingsSheetAndDismisses() {
        let app = launchApp()

        let gear = app.buttons["settingsGear"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Version"].exists, "the About section's version row")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["settingsGear"].waitForExistence(timeout: 5))
    }

    // MARK: - First launch (empty store → the Add-Activity hero)

    func testFirstLaunchShowsTheAddActivityHeroAndOpensTheWizard() {
        // The REAL first launch (no UITEST_SEED_LIVE): an empty store — the
        // approved Add-Activity hero card renders, no request is made, and
        // tapping it opens the wizard directly (no chooser, no templates).
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_LOCATION"])

        XCTAssertTrue(app.staticTexts["headerTime"].waitForExistence(timeout: 5), "the header still renders")
        let hero = app.buttons["addActivitiesButton"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "the Add-Activity hero is the whole state")
        let message = app.staticTexts["firstLaunchMessage"]
        XCTAssertTrue(message.exists, "with its two-paragraph invitation copy")
        XCTAssertTrue(message.label.contains("for any activity you create."),
                      "the owner-approved wording (edited 2026-09-01, pre-archive)")
        XCTAssertEqual(cardCount(in: app), 0, "an empty store never rates — no request, no cards")
        attachScreenshot(app, named: "first-launch-glass")
        XCTAssertFalse(app.staticTexts["Weather Unavailable"].exists, "and it is not an error — no request was made")
        XCTAssertFalse(app.staticTexts["headerTemp"].exists,
                       "no fabricated or placeholder weather while nothing is live")

        hero.tap()
        XCTAssertTrue(app.textFields["editor.name"].waitForExistence(timeout: 5),
                      "the hero opens the wizard directly — the template chooser is gone")
    }

    // MARK: - Error state

    func testServerFailureShowsErrorState() {
        // UITEST_LOCATION matters here: without a resolvable location, the
        // no-location state wins and the failing API is never called — the
        // store must be seeded LIVE or no request happens at all.
        let app = launchApp(arguments: ["UITEST_MOCK_FAILURE", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION"])

        XCTAssertTrue(app.staticTexts["Weather Unavailable"].waitForExistence(timeout: 5),
                      "provider failure renders the ContentUnavailableView error state")
        XCTAssertFalse(app.buttons["card.cycling"].exists)
    }

    // MARK: - Editor wizard flows (ghost add-card straight into the wizard)

    func testGhostAddCardIsVisibleAfterCardsAndOpensTheWizard() {
        let app = launchApp()

        let addCard = app.buttons["addActivityCard"]
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(addCard.waitForExistence(timeout: 5), "ghost add-card renders after the card list")
        addCard.tap()

        XCTAssertTrue(app.textFields["editor.name"].waitForExistence(timeout: 5),
                      "the add card opens the wizard directly — no template chooser in between")
    }

    func testAddFromScratchWalksTheGatedWizard() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["addActivityCard"].tap()

        let next = app.buttons["editor.nextStep"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "empty name + sentinel icon → tab 0 incomplete")

        // Locked-tab no-op: Review is gated behind tabs 0–2.
        app.buttons["editor.tab.3"].tap()
        XCTAssertTrue(app.textFields["editor.name"].exists,
                      "tapping a locked tab does nothing — still on tab 0")
        XCTAssertFalse(app.buttons["editor.save"].exists)

        let nameField = app.textFields["editor.name"]
        nameField.tap()
        nameField.typeText("Padel")
        XCTAssertFalse(next.isEnabled, "a name alone is not enough — an icon must be chosen (the sentinel is gated)")

        // From scratch every category starts collapsed — expand and pick.
        scrollTo(app.staticTexts["Sports"], in: app)
        app.staticTexts["Sports"].tap()
        let icon = app.buttons["icon.figure.tennis"]
        scrollTo(icon, in: app)
        icon.tap()
        XCTAssertTrue(next.isEnabled, "name + icon completes the Name & Icon tab")
        next.tap()

        // Tab 1: one tap = a working Must-have threshold (the old
        // editor.addThreshold flow is gone).
        let metric = app.buttons["metric.temp"]
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "no metric selected yet")
        metric.tap()
        XCTAssertTrue(next.isEnabled, "selecting auto-creates the preset threshold — zero typing")

        // The tap-the-label exact-entry path.
        app.buttons["editor.value.temp"].tap()
        let minField = app.textFields["editor.min.temp"]
        XCTAssertTrue(minField.waitForExistence(timeout: 5))
        XCTAssertEqual(minField.value as? String, "15", "the preset min prefills the field")
        minField.tap()
        minField.typeText("\n")
        next.tap()

        // Tab 2: both wheels always visible; a valid but untouched prefill
        // takes the warn-then-proceed path.
        XCTAssertTrue(app.pickers["editor.startHour"].waitForExistence(timeout: 5),
                      "both hour wheels render on entry")
        XCTAssertTrue(app.pickers["editor.endHour"].exists)
        XCTAssertTrue(next.isEnabled, "the warning path keeps Next Step enabled")
        next.tap()
        XCTAssertTrue(app.staticTexts["editor.rangeWarning"].waitForExistence(timeout: 5),
                      "first press shows the skip warning exactly once")
        next.tap()

        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "second press proceeds to Review")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["Padel"].waitForExistence(timeout: 5),
                      "the scratch-built card renders with its confirmed range")
    }

    func testReviewTabTapTakesTheWarnThenProceedPath() {
        // Plan §6: the SECOND press proceeds for BOTH paths — "presses Next
        // Step (or taps the Review tab)". The Review-tab tap must not loop
        // on the warning. Walked through the scratch wizard (the only add
        // path): tabs 0–1 completed, the Range prefill left untouched.
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["addActivityCard"].tap()

        let nameField = app.textFields["editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Padel")
        scrollTo(app.staticTexts["Sports"], in: app)
        app.staticTexts["Sports"].tap()
        let icon = app.buttons["icon.figure.tennis"]
        scrollTo(icon, in: app)
        icon.tap()
        app.buttons["editor.nextStep"].tap()
        let metric = app.buttons["metric.temp"]
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        metric.tap()
        app.buttons["editor.nextStep"].tap()
        XCTAssertTrue(app.pickers["editor.startHour"].waitForExistence(timeout: 5),
                      "on the Range tab with the untouched 6–10am prefill")

        let reviewTab = app.buttons["editor.tab.3"]
        reviewTab.tap()

        XCTAssertTrue(app.staticTexts["editor.rangeWarning"].waitForExistence(timeout: 5),
                      "first Review-tab tap warns")
        XCTAssertTrue(app.pickers["editor.startHour"].exists,
                      "…landing on the Range tab so the skipped range is visible")
        XCTAssertFalse(app.buttons["editor.save"].exists, "not on Review yet")

        reviewTab.tap()
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 5),
                      "second Review-tab tap proceeds to Review (rangeConfirmed set)")
        XCTAssertFalse(app.staticTexts["editor.rangeWarning"].exists)
        app.buttons["editor.cancel"].tap()
    }

    func testMetricCheckboxesSwitchThresholdModes() {
        // Owner edit 2026-08-30: the mode menu is gone — a selected metric
        // carries two checkboxes, "Priority" and "Show don't calculate".
        let app = launchApp()
        openEditorFromDetail("cycling", in: app)

        let metricsTab = app.buttons["editor.tab.1"]
        XCTAssertTrue(metricsTab.waitForExistence(timeout: 5))
        metricsTab.tap()

        // Cycling's temp threshold is required → Priority arrives checked,
        // with the slider's value label rendered.
        let priority = app.buttons["editor.priority.temp"]
        let showOnly = app.buttons["editor.showOnly.temp"]
        XCTAssertTrue(priority.waitForExistence(timeout: 5))
        XCTAssertTrue(showOnly.exists)
        XCTAssertTrue(priority.isSelected, "a required threshold reads as Priority checked")
        XCTAssertFalse(showOnly.isSelected)
        XCTAssertTrue(app.buttons["editor.value.temp"].exists)

        showOnly.tap()
        XCTAssertFalse(app.buttons["editor.value.temp"].exists,
                       "show don't calculate drops the threshold — the slider goes")
        XCTAssertTrue(showOnly.isSelected)
        XCTAssertFalse(priority.isSelected, "the boxes never both read checked")

        priority.tap()
        XCTAssertTrue(app.buttons["editor.value.temp"].waitForExistence(timeout: 5),
                      "checking Priority re-creates the preset threshold")
        XCTAssertTrue(priority.isSelected)
        XCTAssertFalse(showOnly.isSelected)
        app.buttons["editor.cancel"].tap()
    }

    func testNameFieldWholeRowActivatesTheKeyboard() {
        // Device finding 2026-08-30: only the leading edge of the name row
        // focused the field — the whole row must raise the keyboard.
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["addActivityCard"].tap()

        let nameField = app.textFields["editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "tapping the trailing end of the row focuses the field")
        app.buttons["editor.cancel"].tap()
    }

    // MARK: - Edit + delete via the detail's circles (the card gear is gone)

    func testDetailEditDoorOpensEditorAndEditedLabelReflectsOnCard() {
        let app = launchApp()
        openEditorFromDetail("cycling", in: app)

        app.buttons["editor.tab.0"].tap()
        let nameField = app.textFields["editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Cycling", "edit mode pre-fills the existing Activity")

        nameField.tap()
        nameField.typeText(" Pro")
        // Edit mode: everything is pre-filled and the window exists — all
        // four tabs pass their gates, so Review is one tap away.
        app.buttons["editor.tab.3"].tap()
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // Owner edit 2026-08-30: Review renders the actual dashboard card as
        // a representative preview, not a text summary.
        XCTAssertTrue(app.otherElements["editor.reviewCard"].exists,
                      "the Review tab shows the dashboard card preview")
        save.tap()

        // Back from the detail to the dashboard card.
        XCTAssertTrue(app.buttons["editor.save"].waitForNonExistence(timeout: 5), "the sheet closes")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5), "back on the dashboard")
        XCTAssertTrue(app.staticTexts["Cycling Pro"].waitForExistence(timeout: 5), "the card reflects the edit after refetch")
    }

    func testDeletingLastActivityLandsTheAddHeroNotADeadEnd() {
        let app = launchApp()
        openEditorFromDetail("cycling", in: app)
        // Delete lives on the Review tab now — edit mode unlocks it directly.
        app.buttons["editor.tab.3"].tap()
        scrollTo(app.buttons["editor.delete"], in: app)
        XCTAssertTrue(app.buttons["editor.delete"].waitForExistence(timeout: 5))
        app.buttons["editor.delete"].tap()
        // confirmationDialog buttons surface twice in the hierarchy — firstMatch disambiguates
        XCTAssertTrue(app.buttons["editor.confirmDelete"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["editor.confirmDelete"].firstMatch.tap()

        // The deleted Activity's detail pops itself — back on the dashboard.
        XCTAssertTrue(app.buttons["card.fishing-lite"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["card.cycling"].exists, "deleted card is gone")

        openEditorFromDetail("fishing-lite", in: app)
        app.buttons["editor.tab.3"].tap()
        scrollTo(app.buttons["editor.delete"], in: app)
        XCTAssertTrue(app.buttons["editor.delete"].waitForExistence(timeout: 5))
        app.buttons["editor.delete"].tap()
        // confirmationDialog buttons surface twice in the hierarchy — firstMatch disambiguates
        XCTAssertTrue(app.buttons["editor.confirmDelete"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["editor.confirmDelete"].firstMatch.tap()

        // Deleting the last Activity lands the Add-Activity hero — nothing
        // re-seeds (the template showcase is gone), and the hero keeps the
        // standing next action so it is never a dead end.
        XCTAssertTrue(app.buttons["card.fishing-lite"].waitForNonExistence(timeout: 5),
                      "the deleted card is gone")
        XCTAssertTrue(app.buttons["addActivitiesButton"].waitForExistence(timeout: 5),
                      "the emptied store shows the Add-Activity hero, not a dead end")
        XCTAssertTrue(app.staticTexts["firstLaunchMessage"].exists)
        XCTAssertEqual(cardCount(in: app), 0)
    }

    // MARK: - Persistence across relaunch

    func testAuthoredListPersistsAcrossRelaunch() {
        // Delete one of the two seeded activities…
        var app = launchApp()
        openEditorFromDetail("cycling", in: app)
        app.buttons["editor.tab.3"].tap()
        scrollTo(app.buttons["editor.delete"], in: app)
        XCTAssertTrue(app.buttons["editor.delete"].waitForExistence(timeout: 5))
        app.buttons["editor.delete"].tap()
        XCTAssertTrue(app.buttons["editor.confirmDelete"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["editor.confirmDelete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["card.cycling"].waitForNonExistence(timeout: 5))

        app.terminate()
        // No RESET and no SEED_LIVE — the persisted authored list must feed
        // the relaunch on its own.
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_LOCATION"])

        XCTAssertTrue(app.buttons["card.fishing-lite"].waitForExistence(timeout: 5),
                      "the surviving Activity feeds the relaunch")
        XCTAssertFalse(app.buttons["card.cycling"].exists,
                       "the authored list (not any seed) survives a relaunch — the deletion sticks")
    }

    func testCachedLastResolvedFeedsARelaunchWithNothingElse() {
        // First run: place a city so a successful rating persists the cache…
        var app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE"])
        let place = app.buttons["placeLocationButton"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        pickCity("Dubai Marina", in: app)
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))

        // …then clear home, so on relaunch only the cache can feed the chain.
        app.buttons["settingsGear"].tap()
        let clear = app.buttons["settings.useCurrentLocation"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5),
                      "with home cleared and no GPS, the cache keeps the dashboard rated")

        app.terminate()
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS"]) // no RESET, no UITEST_LOCATION

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5),
                      "a previously successful location renders real data on a bare relaunch")
        XCTAssertTrue(app.staticTexts["DUBAI MARINA"].exists, "the cached name labels the header")
        XCTAssertFalse(app.buttons["enableLocationButton"].exists, "not the empty state")
    }

    // MARK: - Home location

    /// Searches the city picker (as-you-type — no Search button) and taps the
    /// first mock result. The picker sheet must already be on screen.
    private func pickCity(_ name: String, in app: XCUIApplication) {
        let search = app.textFields["cityPicker.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(name)
        let result = app.buttons["cityPicker.result.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), "the (mock) geocoder returns a debounced result")
        result.tap()
    }

    func testHomeLocationPersistsAcrossRelaunchAndClears() {
        var app = launchApp()
        XCTAssertTrue(app.buttons["settingsGear"].waitForExistence(timeout: 5))
        app.buttons["settingsGear"].tap()

        let setHome = app.buttons["settings.setHome"]
        XCTAssertTrue(setHome.waitForExistence(timeout: 5))
        setHome.tap()
        pickCity("Dubai Marina", in: app)
        XCTAssertTrue(app.staticTexts["Dubai Marina"].waitForExistence(timeout: 5), "home location is set")
        app.buttons["Done"].tap()

        app.terminate()
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_LOCATION"]) // no RESET
        XCTAssertTrue(app.buttons["settingsGear"].waitForExistence(timeout: 5))
        app.buttons["settingsGear"].tap()
        XCTAssertTrue(app.staticTexts["Dubai Marina"].waitForExistence(timeout: 5), "home location survives a relaunch")

        app.buttons["settings.useCurrentLocation"].tap()
        XCTAssertTrue(app.staticTexts["Using current location"].waitForExistence(timeout: 5), "clearing returns to GPS")
    }

    // MARK: - No-location onboarding

    func testNoLocationShowsSkeletonsAndCTAsWithNoWeather() {
        // No UITEST_LOCATION: the provider never resolves. Seeded LIVE
        // because the first launch is the Add-Activity hero — no-location
        // surfaces once a confirmed range makes a fetch worth attempting.
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE"])

        XCTAssertTrue(app.buttons["enableLocationButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["placeLocationButton"].exists)
        XCTAssertTrue(app.staticTexts["NO LOCATION"].exists, "the header is honest about the missing location")
        XCTAssertTrue(app.otherElements["skeletonCard.0"].exists, "grayed skeleton cards render (spec §2)")
        XCTAssertTrue(app.otherElements["skeletonCard.1"].exists)
        XCTAssertEqual(cardCount(in: app), 0, "no rated cards")
        XCTAssertFalse(app.staticTexts["headerTemp"].exists,
                       "the header's weather rows are gone entirely — not just showing placeholders")
    }

    func testLiveActivitiesWithLocationDeniedShowTheSameEmptyState() {
        // A TRUE fresh install shows the Add-Activity hero (location not
        // yet needed), so the denied case is pinned with live activities. The
        // provider reports .denied with no fix — the CTA would deep-link to
        // system Settings (not provable hermetically), but the honest empty
        // state must render.
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION_DENIED"])

        XCTAssertTrue(app.buttons["enableLocationButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["placeLocationButton"].exists)
        XCTAssertTrue(app.staticTexts["NO LOCATION"].exists)
        XCTAssertEqual(cardCount(in: app), 0, "no weather data shown")
        XCTAssertFalse(app.staticTexts["headerTemp"].exists)
    }

    func testPlacingOwnLocationLoadsRatings() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE"])

        let place = app.buttons["placeLocationButton"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        pickCity("Dubai Marina", in: app)

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5),
                      "picking a city rates immediately — the home-change sink refetches")
        XCTAssertTrue(app.staticTexts["DUBAI MARINA"].exists, "the picked city names the header")
    }

    // MARK: - Detail page

    // #25: the two edit doors open the wizard on their own tab, not on the
    // Name & Icon tab the "+" path starts at.
    func testDetailEditDoorsLandOnTheirOwnWizardTab() {
        let app = launchApp()

        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))

        app.buttons["detail.editRange"].tap()
        XCTAssertTrue(app.pickers["editor.startHour"].waitForExistence(timeout: 5),
                      "Edit range opens straight onto the Range tab")
        XCTAssertFalse(app.textFields["editor.name"].exists, "not the Name & Icon tab")
        app.buttons["editor.cancel"].tap()

        XCTAssertTrue(app.buttons["detail.editMetrics"].waitForExistence(timeout: 5))
        app.buttons["detail.editMetrics"].tap()
        XCTAssertTrue(app.buttons["metric.temp"].waitForExistence(timeout: 5),
                      "Edit metrics opens straight onto the Metrics tab")
        XCTAssertFalse(app.pickers["editor.startHour"].exists, "not the Range tab")
        XCTAssertFalse(app.textFields["editor.name"].exists, "not the Name & Icon tab")
        app.buttons["editor.cancel"].tap()
    }

    /// Activity Detail v3 (approved frames `456:358` / `464:2348`, + the
    /// 2026-10-02 day-jump frame `508:417`, + the build-8 hero carousel —
    /// owner rulings 2026-10-31 / 2026-11-01): opens on TODAY — the week-dot
    /// row under the nav, hero (day-score ring + rating word + `−` · Range
    /// pill row · `+`), metric cards averaging the chosen hours, then the
    /// Edit list. The pill row is a native scroll; the whole Range-length
    /// span slides one hour per press, and once it leaves the Range the score
    /// ring becomes the return affordance (no capsule, no Calculate button).
    func testDetailV3ShowsDotRowHeroCarouselMetricCardsAndJumpsDays() {
        let app = launchApp()

        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))

        // Hero: the DAY score + the day's rating word, and the carousel's
        // span opening ON the Range (Cycling 6–10am = idx 2..<6 today).
        XCTAssertEqual(app.otherElements["detail.score"].label, "Perfect, score 86 out of 100")
        XCTAssertTrue(app.staticTexts["Perfect"].exists, "the rating word returns on the detail")
        let row = app.descendants(matching: .any)["detail.hourStrip"]
        XCTAssertTrue(row.exists)
        XCTAssertEqual(row.label, "Hours 6am to 10am", "the span opens on the Range")
        XCTAssertFalse(app.staticTexts["detail.selectedHour"].exists,
                       "the old big hour label is gone — the hero is ring + word + pill row")
        let back = app.buttons["detail.stepBack"]
        let forward = app.buttons["detail.stepForward"]
        XCTAssertTrue(back.exists)
        XCTAssertTrue(forward.exists)
        XCTAssertFalse(app.buttons["detail.returnToRange"].exists,
                       "no return control while the span sits on the Range")
        // The line under the row names the hours the cards show (owner
        // ruling 2026-11-04): on the Range it reads the Range itself. The
        // launch helper pins the clock (`UITEST_NOW`) to 4:30am on the June-
        // 2026 mock's day, before the Range — without the pin the real clock
        // is past it and the line would read "· Time passed" (that wording
        // is covered by `testDetailLineReadsTimePassedOnceTheRangeHasEnded`).
        let line = app.staticTexts["detail.rangeLine"]
        XCTAssertTrue(line.exists)
        XCTAssertEqual(line.label, "Your range 6 – 10am")

        // ONE metric card per displayMetric — the grid is not capped at the
        // frames' three. Cycling shows temp/wind/rain/uV.
        XCTAssertTrue(app.otherElements["detail.metric.temp"].exists)
        XCTAssertTrue(app.otherElements["detail.metric.windSpeed"].exists)
        XCTAssertTrue(app.otherElements["detail.metric.rainFall"].exists)
        let uv = app.otherElements["detail.metric.uV"]
        XCTAssertTrue(uv.exists, "a fourth metric gets a fourth card, never truncated away")
        let cards = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.metric.'"))
        XCTAssertEqual(cards.count, 4, "one card per displayMetric, in order")
        // The mock reads UV 3 on every hour except idx 6 (UV 7): the Range's
        // average is 3.
        XCTAssertTrue(uv.label.hasSuffix("UV 3"), "got \(uv.label)")

        // + slides the WHOLE span one hour (7–11am); the cards re-average live
        // ((3 + 3 + 3 + 7) / 4 = 4); the day score does NOT follow the span.
        forward.tap()
        XCTAssertTrue(waitForLabel(row, "Hours 7am to 11am"), "got \(row.label)")
        XCTAssertTrue(waitForLabel(uv, suffix: "UV 4"), "the cards average the chosen hours — got \(uv.label)")
        XCTAssertEqual(app.otherElements["detail.score"].label, "Perfect, score 86 out of 100",
                       "the hero ring shows the DAY score, unchanged by the span")
        XCTAssertEqual(line.label, "Your range 6 – 10am",
                       "the Range lives in one place and never changes with the span")

        // Off the Range the line grows its return button at its end (owner
        // rulings 2026-11-04); tapping it springs home.
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Calculate'")).firstMatch.exists,
                       "no Calculate button — the cards are live")
        let returnControl = app.buttons["detail.returnToRange"]
        XCTAssertTrue(returnControl.waitForExistence(timeout: 2))
        XCTAssertEqual(returnControl.label, "Return to your range")
        XCTAssertFalse(returnControl.frame.intersects(app.otherElements["detail.score"].frame),
                       "the return button sits at the line's end, not on the ring")
        XCTAssertGreaterThan(returnControl.frame.midX, line.frame.maxX - 1,
                             "the return button trails the line")
        returnControl.tap()
        XCTAssertTrue(waitForLabel(row, "Hours 6am to 10am"), "got \(row.label)")
        XCTAssertTrue(waitForLabel(uv, suffix: "UV 3"), "got \(uv.label)")
        XCTAssertTrue(waitForLabel(line, "Your range 6 – 10am"), "got \(line.label)")
        XCTAssertFalse(returnControl.waitForExistence(timeout: 1), "gone once back on the Range")

        // − walks back to the walk start (today's first forecast hour, 4am =
        // idx 0) and dims there: two presses from the 6am Range start.
        XCTAssertTrue(back.isEnabled)
        back.tap()
        XCTAssertTrue(waitForLabel(row, "Hours 5am to 9am"), "got \(row.label)")
        XCTAssertTrue(back.isEnabled)
        back.tap()
        XCTAssertTrue(waitForLabel(row, "Hours 4am to 8am"), "got \(row.label)")
        XCTAssertFalse(back.isEnabled, "− dims when the span starts at the first walkable hour")

        // A horizontal drag scrolls the row natively and the span follows
        // (finger-left = later hours, snapping by pill pitch).
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        XCTAssertTrue(waitForLabel(row, notEqual: "Hours 4am to 8am"), "the drag moved the span later")
        XCTAssertTrue(back.isEnabled)

        // The Edit doors stay.
        XCTAssertTrue(app.buttons["detail.editRange"].exists)
        XCTAssertEqual(app.buttons["detail.editMetrics"].label, "Edit metrics",
                       "no \u{201C}& thresholds\u{201D}")

        // Week rows and the hour grid are gone.
        let dayRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.day.'"))
        XCTAssertEqual(dayRows.count, 0, "the week rows were removed (today-only)")
        XCTAssertFalse(app.otherElements["detail.hours.0"].exists, "the hour grid was removed")
        XCTAssertFalse(app.staticTexts["6 – 10am daily"].exists,
                       "the old setup card's range line is gone — the hero owns the hours now")

        // Day-jump (spec 05). Mock fixture: forecast 2026-06-19T00:00Z = 4am
        // Fri in Dubai, 56 hours → day 0 = idx 0..<20, day 1 = 20..<44,
        // day 2 = 44..<56 (Sun 21 Jun 00:00–12:00). Cycling (6–10am) day 2
        // Range = idx 50..<54 → the carousel re-opens on it. Mock cycling
        // day 2 is rating-null with score 1; day 0 is Perfect 86.
        XCTAssertTrue(app.descendants(matching: .any)["detail.weekDot"].exists,
                      "the week-dot row sits under the nav")
        let dayTwo = app.buttons["detail.weekDot.2"]
        XCTAssertTrue(dayTwo.exists)
        dayTwo.tap()
        XCTAssertEqual(app.otherElements["detail.score"].label, "No Window, score 1 out of 100",
                       "the hero re-reads for the jumped day")
        XCTAssertTrue(waitForLabel(row, "Hours 6am to 10am"),
                      "a jump re-opens the span on that day's Range — got \(row.label)")
        XCTAssertFalse(app.buttons["detail.returnToRange"].exists)

        app.buttons["detail.weekDot.0"].tap()
        XCTAssertEqual(app.otherElements["detail.score"].label, "Perfect, score 86 out of 100",
                       "back to today")
        XCTAssertTrue(waitForLabel(row, "Hours 6am to 10am"), "got \(row.label)")
    }

    /// Owner rulings 2026-11-04: the detail opens with the full Range on the
    /// row and "Your range …" under it; two + presses leave that line
    /// unchanged and add the return button at its end. Attaches the two
    /// screenshots the owner reviews (the launch helper's `UITEST_NOW` pin
    /// puts the clock at 4:30am on the fixture's day, so the pills show their
    /// live tier colours rather than passed-grey).
    func testDetailLineFollowsTheSpanAndScreenshotsTheHero() {
        let app = launchApp()
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))

        let row = app.descendants(matching: .any)["detail.hourStrip"]
        let line = app.staticTexts["detail.rangeLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 3))
        XCTAssertEqual(row.label, "Hours 6am to 10am", "the full Range is on the row")
        XCTAssertEqual(line.label, "Your range 6 – 10am")
        attachScreenshot(app, named: "detail-at-rest")

        let forward = app.buttons["detail.stepForward"]
        forward.tap()
        XCTAssertTrue(waitForLabel(row, "Hours 7am to 11am"), "got \(row.label)")
        forward.tap()
        XCTAssertTrue(waitForLabel(row, "Hours 8am to 12pm"), "got \(row.label)")
        XCTAssertTrue(app.buttons["detail.returnToRange"].waitForExistence(timeout: 2))
        XCTAssertEqual(line.label, "Your range 6 – 10am", "the line never reads the span")
        // Let the springs and the line's crossfade settle before the capture.
        Thread.sleep(forTimeInterval: 0.6)
        attachScreenshot(app, named: "detail-after-two-plus")

        app.buttons["detail.returnToRange"].tap()
        XCTAssertTrue(waitForLabel(line, "Your range 6 – 10am"), "got \(line.label)")
        XCTAssertTrue(waitForLabel(row, "Hours 6am to 10am"), "got \(row.label)")
    }

    /// "· Time passed" (owner ruling 2026-11-04): pinned to noon Dubai on the
    /// fixture's day 0, after Cycling's 6–10am, the line names the Range as
    /// ended. Wording only — no accessibility surface exposes the pills' or
    /// the card strip's tier colour, so the grey is checked by eye in the
    /// attached screenshot.
    func testDetailLineReadsTimePassedOnceTheRangeHasEnded() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION",
                                        "UITEST_NOW=2026-06-19T08:00:00Z"])
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))

        let line = app.staticTexts["detail.rangeLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["detail.hourStrip"].label, "Hours 6am to 10am")
        XCTAssertEqual(line.label, "Your range 6 – 10am · Time passed")
        attachScreenshot(app, named: "detail-time-passed")
    }

    /// Span scoring (owner rulings 2026-11-04): away from the Range, the
    /// glass "Score 7 – 11am" capsule (row 2, under the fixed Range line)
    /// scores the shown hours on the server. The mock answers a seeded
    /// activity sent with a non-seed window as Good `60 + startHour` (7–11am
    /// → 67, 8am–12pm → 68 — see `ForecastResponse.uiTestFixture`). The ring
    /// then reads the span's score and the capsule becomes "Scored 7 – 11am"
    /// — the span is named once, with no caption under the word; a new span
    /// brings the capsule back and the return button clears it.
    func testScoreSpanScoresTheShownHoursAndClearsOnReturn() {
        let app = launchApp()
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))

        let score = app.otherElements["detail.score"]
        let scoreButton = app.buttons["detail.scoreSpan"]
        let scored = app.staticTexts["detail.scoredSpan"]
        let line = app.staticTexts["detail.rangeLine"]
        let row = app.descendants(matching: .any)["detail.hourStrip"]
        XCTAssertEqual(score.label, "Perfect, score 86 out of 100")
        XCTAssertFalse(scoreButton.exists, "no score capsule on the Range — the ring already scores it")
        XCTAssertFalse(scored.exists)

        app.buttons["detail.stepForward"].tap()
        XCTAssertTrue(waitForLabel(row, "Hours 7am to 11am"), "got \(row.label)")
        XCTAssertTrue(scoreButton.waitForExistence(timeout: 2))
        XCTAssertEqual(scoreButton.label, "Score 7 to 11am", "the capsule names the span")
        XCTAssertEqual(line.label, "Your range 6 – 10am", "row 1 keeps the Range")
        // midY: the capsule's accessibility frame is its padded 44pt target.
        XCTAssertGreaterThan(scoreButton.frame.midY, line.frame.maxY,
                             "the capsule sits under the fixed Range line")
        XCTAssertEqual(scoreButton.frame.minX, line.frame.minX, accuracy: 0.5,
                       "the capsule is flush with the Range text's leading edge")
        XCTAssertFalse(app.staticTexts["detail.spanCaption"].exists, "the caption under the word is gone")
        // The offered capsule, for the by-eye/pixel alignment check against
        // the Range text's leading edge. Let the fade settle first.
        Thread.sleep(forTimeInterval: 0.6)
        attachScreenshot(app, named: "detail-span-offered")

        scoreButton.tap()
        XCTAssertTrue(scored.waitForExistence(timeout: 3), "the capsule becomes the quiet Scored text")
        XCTAssertEqual(scored.label, "Scored 7 – 11am")
        XCTAssertTrue(waitForLabel(score, "Good, score 67 out of 100 for 7 to 11am"), "got \(score.label)")
        XCTAssertTrue(app.staticTexts["Good"].exists, "the word takes the span's verdict")
        XCTAssertTrue(scoreButton.waitForNonExistence(timeout: 2), "the capsule goes once the span has a score")
        XCTAssertFalse(app.staticTexts["detail.spanCaption"].exists, "the span is named once, in row 2")
        XCTAssertEqual(line.label, "Your range 6 – 10am")
        attachScreenshot(app, named: "detail-span-scored")

        // A new span clears the score: the ring is the day's again, the
        // capsule is back for the new span.
        app.buttons["detail.stepForward"].tap()
        XCTAssertTrue(waitForLabel(row, "Hours 8am to 12pm"), "got \(row.label)")
        XCTAssertTrue(waitForLabel(score, "Perfect, score 86 out of 100"), "got \(score.label)")
        XCTAssertTrue(scored.waitForNonExistence(timeout: 2), "a stale span score never stays")
        XCTAssertTrue(scoreButton.waitForExistence(timeout: 2))
        XCTAssertEqual(scoreButton.label, "Score 8am to 12pm")

        scoreButton.tap()
        XCTAssertTrue(waitForLabel(score, "Good, score 68 out of 100 for 8am to 12pm"), "got \(score.label)")
        XCTAssertTrue(scored.waitForExistence(timeout: 2))
        XCTAssertEqual(scored.label, "Scored 8am – 12pm")

        // The return button at the line's end clears it too.
        let returnControl = app.buttons["detail.returnToRange"]
        XCTAssertGreaterThan(returnControl.frame.midX, line.frame.maxX - 1, "the return button trails the line")
        returnControl.tap()
        XCTAssertTrue(waitForLabel(row, "Hours 6am to 10am"), "got \(row.label)")
        XCTAssertTrue(waitForLabel(score, "Perfect, score 86 out of 100"), "got \(score.label)")
        XCTAssertTrue(scored.waitForNonExistence(timeout: 2), "row 2 goes on return")
        XCTAssertFalse(scoreButton.exists, "no capsule back on the Range")
        XCTAssertTrue(returnControl.waitForNonExistence(timeout: 2), "no return button on the Range")
    }

    /// Item 2: pulling the dashboard list down refreshes it in place — the
    /// cards stay rendered through and after the pull (the mock refetch).
    func testDashboardPullToRefreshKeepsTheListRendered() {
        let app = launchApp()
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: 320)))
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the list is still rendered after the pull")
        XCTAssertTrue(app.buttons["card.fishing-lite"].exists)
        XCTAssertFalse(app.staticTexts["Checking conditions…"].exists,
                       "a pull never swaps the list for the full-screen spinner")
        card.tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5),
                      "the refreshed list is live")
    }

    /// Build 8 fade slice: the band melt is a backdrop under the list — the
    /// first card is hittable inside the melt zone (its top edge), the
    /// header still renders over the band, and a screenshot of the resting
    /// dashboard is kept for review.
    func testBandMeltNeverInterceptsTheFirstCard() {
        let app = launchApp()
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["headerTime"].exists)
        XCTAssertTrue(card.isHittable, "the melt must not cover the first card")
        attachScreenshot(app, named: "dashboard-band-melt")
        // A tap near the card's top edge — inside the melt's strongest band.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.1)).tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5),
                      "the tap reached the card, not the backdrop")
    }

    /// Build 8 dark mode: `UITEST_APPEARANCE=dark` pins the scheme (the app
    /// itself follows the system). Walks dashboard → detail → one + (the
    /// Score capsule shows) → back, keeping a screenshot of each for the
    /// owner's by-eye check against the approved dark frames — no
    /// accessibility surface exposes a colour.
    func testDarkAppearanceWalksDashboardAndDetail() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION",
                                        "UITEST_APPEARANCE=dark"])
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["headerTime"].exists)
        XCTAssertTrue(app.buttons["card.fishing-lite"].exists)
        assertHeaderNumeralSwap(app)
        attachScreenshot(app, named: "header-dark")
        attachScreenshot(app, named: "dashboard-dark")

        card.tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))
        let row = app.descendants(matching: .any)["detail.hourStrip"]
        XCTAssertTrue(app.staticTexts["detail.rangeLine"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["detail.score"].exists)
        XCTAssertTrue(app.otherElements["detail.metric.temp"].exists)
        Thread.sleep(forTimeInterval: 0.6)
        attachScreenshot(app, named: "detail-dark")

        app.buttons["detail.stepForward"].tap()
        XCTAssertTrue(waitForLabel(row, "Hours 7am to 11am"), "got \(row.label)")
        XCTAssertTrue(app.buttons["detail.scoreSpan"].waitForExistence(timeout: 2))
        Thread.sleep(forTimeInterval: 0.6)
        attachScreenshot(app, named: "detail-dark-span")

        app.navigationBars["Cycling"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5), "back returns to the dashboard")
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Polls an element's accessibility label — the row's span follows a
    /// native scroll, so a read straight after a tap can race the settle.
    private func waitForLabel(_ element: XCUIElement,
                              _ label: String? = nil,
                              suffix: String? = nil,
                              notEqual: String? = nil,
                              timeout: TimeInterval = 3) -> Bool {
        let predicate: NSPredicate
        if let label {
            predicate = NSPredicate(format: "label == %@", label)
        } else if let suffix {
            predicate = NSPredicate(format: "label ENDSWITH %@", suffix)
        } else {
            predicate = NSPredicate(format: "label != %@", notEqual ?? "")
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Push opt-in client

    /// Polls an XCUI switch for a target value — the enable flow completes
    /// asynchronously (permission → registration), so a plain read races it.
    private func waitForSwitchValue(_ element: XCUIElement, _ value: String,
                                    timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func tapToggle(_ toggle: XCUIElement) {
        // The identifier sits on the whole Toggle row — tap the nested switch.
        let control = toggle.switches.firstMatch
        (control.exists ? control : toggle).tap()
    }

    func testNotificationsToggleEnablesWhenPromptGranted() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.buttons["settingsGear"].tap()
        let toggle = app.switches["settings.notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the NOTIFICATIONS row exists")
        XCTAssertEqual(toggle.value as? String, "0", "off until the user opts in — no inert switches")

        tapToggle(toggle)

        // The mock authorizer grants — the toggle lands ON only when the
        // permission flow actually completes.
        XCTAssertTrue(waitForSwitchValue(toggle, "1"), "granted prompt → enabled")
    }

    func testNotificationsToggleStaysOffWhenPromptDenied() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION", "UITEST_PUSH_DENY"])

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.buttons["settingsGear"].tap()
        let toggle = app.switches["settings.notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        tapToggle(toggle)

        XCTAssertFalse(waitForSwitchValue(toggle, "1", timeout: 2),
                       "denied prompt → the switch reverts; it never lies ON")
    }

    func testNotificationsToggleRoutesThroughCityPickerWithoutALocation() {
        // GPS denied, no home: routes the opt-in through onboarding — here
        // the city-picker door. Cancelling abandons it.
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION_DENIED"])

        XCTAssertTrue(app.buttons["settingsGear"].waitForExistence(timeout: 5))
        app.buttons["settingsGear"].tap()
        let toggle = app.switches["settings.notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        tapToggle(toggle)

        XCTAssertTrue(app.textFields["cityPicker.search"].waitForExistence(timeout: 5),
                      "no real location → the city picker opens before any permission prompt")
        app.buttons["cityPicker.cancel"].tap()
        XCTAssertFalse(waitForSwitchValue(toggle, "1", timeout: 2),
                       "dismissing the picker without a home abandons the opt-in")
    }

    func testPushCalloutDeepLinksToSettingsNotifications() {
        let app = launchApp()

        let callout = app.buttons["pushCallout"]
        XCTAssertTrue(callout.waitForExistence(timeout: 5),
                      "the one-time callout sits above the card list")
        // The hyphen is dropped in UI copy only — docs keep "Perfect-window
        // alert".
        XCTAssertTrue(app.staticTexts["Get a morning digest + Perfect window alerts"].exists)

        callout.tap()

        XCTAssertTrue(app.switches["settings.notifications"].waitForExistence(timeout: 5),
                      "the callout deep-links to the Settings Notifications row")
    }

    func testPushCalloutDismissIsRememberedAcrossRelaunch() {
        var app = launchApp()

        let dismiss = app.buttons["pushCallout.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()
        XCTAssertFalse(app.buttons["pushCallout"].exists, "dismissed on the spot")

        // Relaunch WITHOUT UITEST_RESET — one-time means gone for good.
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_SEED_LIVE", "UITEST_LOCATION"])
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pushCallout"].exists, "the dismissal persists")
    }

    // MARK: - Beta feedback — disclaimer banner + suggestion sheet

    func testBetaBannerAndSuggestionButtonRenderWhenGateOn() {
        // Pinned Light (absent = the simulator's appearance) so the shot below
        // is the light glass: the header gear, the suggestion capsule, the
        // add capsule after the list.
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION", "UITEST_BETA", "UITEST_APPEARANCE=light"])

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "dashboard-glass-light")
        let banner = app.otherElements["betaBanner"]
        XCTAssertTrue(banner.exists, "the disclaimer card renders on a beta (dev/TestFlight) install")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'early build for Time it'")).firstMatch.exists,
                      "the owner's round-2 disclaimer copy")
        XCTAssertTrue(app.buttons["betaBanner.suggest"].exists, "with its suggestion entry point")
        // Stacking order: the push callout first, banner below.
        XCTAssertLessThan(app.buttons["pushCallout"].frame.minY, banner.frame.minY)
    }

    func testBetaBannerAbsentWhenGateOff() {
        // No UITEST_BETA — the same archive's App Store face.
        let app = launchApp()

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["betaBanner"].exists, "App Store installs never see beta surfaces")
        XCTAssertFalse(app.buttons["betaBanner.suggest"].exists)
    }

    func testSuggestionSheetHappyPathSendsConfirmsAndDismisses() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION", "UITEST_BETA"])

        let suggest = app.buttons["betaBanner.suggest"]
        XCTAssertTrue(suggest.waitForExistence(timeout: 5))
        suggest.tap()

        let editor = app.textViews["feedback.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "the sheet opens on a text editor")
        let send = app.buttons["feedback.send"]
        XCTAssertFalse(send.isEnabled, "an empty message cannot send")
        editor.tap()
        editor.typeText("Add wind direction to the cards")
        XCTAssertTrue(send.isEnabled)
        send.tap()

        XCTAssertTrue(app.staticTexts["feedback.success"].waitForExistence(timeout: 5),
                      "success shows a brief confirmation")
        XCTAssertTrue(app.staticTexts["feedback.success"].waitForNonExistence(timeout: 5),
                      "then the sheet dismisses itself")
        XCTAssertTrue(suggest.isHittable, "back on the dashboard")
    }

    func testSuggestionSendFailureKeepsTypedTextAndOffersRetry() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION", "UITEST_BETA", "UITEST_FEEDBACK_FAIL"])

        let suggest = app.buttons["betaBanner.suggest"]
        XCTAssertTrue(suggest.waitForExistence(timeout: 5))
        suggest.tap()

        let editor = app.textViews["feedback.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Keep this text")
        app.buttons["feedback.send"].tap()

        XCTAssertTrue(app.staticTexts["feedback.error"].waitForExistence(timeout: 5),
                      "the non-204 surfaces its error")
        XCTAssertEqual(editor.value as? String, "Keep this text", "a typed suggestion is never discarded")
        XCTAssertTrue(app.buttons["feedback.send"].isEnabled, "Send stays as the retry")
        XCTAssertFalse(app.staticTexts["feedback.success"].exists)
    }
}
