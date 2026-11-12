import UIKit
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
/// - `contentSize:` (launch helper) passes the system launch argument
///   `-UIPreferredContentSizeCategoryName <category>` — the app's text size
///   for that run, with no app code (the Dynamic Type pass, build 8).
final class TimeItUITests: XCTestCase {

    // MARK: - Launch helpers

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 4:30am Dubai on the fixture's day 0 — before every seeded Range, so
    /// every run (whatever its other arguments) shows the live look.
    private static let pinnedNow = "UITEST_NOW=2026-06-19T00:30:00Z"

    private func launchApp(arguments: [String] = ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION"],
                           contentSize: UIContentSizeCategory? = nil,
                           skipOpening: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        // The clock pin rides along unless the caller pins its own instant.
        let pinsOwnClock = arguments.contains { $0.hasPrefix("UITEST_NOW=") }
        app.launchArguments = pinsOwnClock ? arguments : arguments + [Self.pinnedNow]
        // The opening sequence is skipped except where a test watches it.
        if skipOpening { app.launchArguments.append("UITEST_SKIP_OPENING") }
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        }
        app.launch()
        return app
    }

    /// The only edit door (owner ruling 2026-10-06 #2 — the card gear is
    /// gone): tap the card, then the detail's Edit metrics circle. Edit mode
    /// unlocks every wizard tab, so callers tab on from there.
    private func openEditorFromDetail(_ activityId: String, in app: XCUIApplication) {
        let card = app.buttons["card.\(activityId)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        tapCardBody(card)
        let editMetrics = app.buttons["detail.editMetrics"]
        XCTAssertTrue(editMetrics.waitForExistence(timeout: 5), "the detail's edit circles")
        editMetrics.tap()
        XCTAssertTrue(app.buttons["editor.cancel"].waitForExistence(timeout: 5), "the editor sheet is up")
    }

    /// Opens the detail through the card body (the ring's corner) — the
    /// card's week dots are their own day-jump buttons (note 16), so a
    /// centre tap can land on one and open a later day.
    private func tapCardBody(_ card: XCUIElement) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.25)).tap()
    }

    /// Next until Review (edit mode passes every gate; an unconfirmed Range
    /// takes its second press).
    private func advanceToReview(in app: XCUIApplication) {
        let save = app.buttons["editor.save"]
        var presses = 0
        while !save.exists, presses < 8 {
            app.buttons["editor.nextStep"].tap()
            presses += 1
        }
        XCTAssertTrue(save.waitForExistence(timeout: 5), "on the Review step")
    }

    /// Back until the Name step.
    private func goBackToName(in app: XCUIApplication) {
        let name = app.textFields["editor.name"]
        var presses = 0
        while !name.exists, presses < 6 {
            app.buttons["editor.back"].tap()
            presses += 1
        }
        XCTAssertTrue(name.waitForExistence(timeout: 5), "on the Name step")
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
        tapCardBody(card)

        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5), "detail uses the activity label as title")

        app.navigationBars["Cycling"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5), "back returns to the dashboard")
    }

    /// Fresh-eyes note 16: a card's week dot opens the detail on THAT day,
    /// not today. Mock cycling day 2 is rating-null with score 1; day 0 is
    /// Perfect 86 — so the hero proves which day opened.
    func testCardWeekDotOpensTheDetailOnThatDay() {
        let app = launchApp()

        let dot = app.buttons["weekDots.cycling.2"]
        XCTAssertTrue(dot.waitForExistence(timeout: 5), "the card's data dots are buttons")
        XCTAssertTrue(dot.isHittable)
        dot.tap()

        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5), "the detail opened")
        XCTAssertTrue(app.buttons["detail.weekDot.2"].isSelected, "the tapped day is the selected day")
        XCTAssertEqual(app.otherElements["detail.score"].label, "No Window, score 1 out of 100",
                       "the hero reads the tapped day, not today")

        // A plain card tap (on the ring, away from the dots) still opens today.
        app.navigationBars["Cycling"].buttons.firstMatch.tap()
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        tapCardBody(card)
        XCTAssertTrue(app.buttons["detail.weekDot.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.weekDot.0"].isSelected, "a card tap opens today")
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
        // POLISH item 3: a single "+" — no words on screen, still named for
        // VoiceOver, still the HIG 44pt target.
        XCTAssertEqual(addCard.label, "Add Activity")
        XCTAssertFalse(addCard.staticTexts["Add Activity"].exists, "the slot shows the glyph alone")
        XCTAssertGreaterThanOrEqual(addCard.frame.height, 44)
        XCTAssertGreaterThanOrEqual(addCard.frame.width, 44)
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
        XCTAssertFalse(next.isEnabled, "empty name + sentinel icon → step 1 incomplete")
        XCTAssertFalse(app.buttons["editor.back"].exists, "no Back on the first step")
        XCTAssertFalse(app.buttons["editor.tab.0"].exists, "the tab strip is gone — a progress bar instead")

        let nameField = app.textFields["editor.name"]
        nameField.tap()
        nameField.typeText("Padel")
        XCTAssertFalse(next.isEnabled, "a name alone is not enough — an icon must be chosen (the sentinel is gated)")

        // From scratch the first category (Sports) starts open.
        let icon = app.buttons["icon.figure.tennis"]
        scrollTo(icon, in: app)
        icon.tap()
        XCTAssertTrue(next.isEnabled, "name + icon completes the Name step")
        next.tap()

        // Metrics: one tap picks and opens the tile to its slider.
        let metric = app.buttons["metric.temp"]
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "no metric picked yet")
        metric.tap()
        XCTAssertFalse(next.isEnabled, "one metric is not enough (owner ruling 2026-11-11)")
        XCTAssertTrue(app.staticTexts["editor.metricsGate"].exists, "the hint line under the grid")

        // The tap-the-label exact-entry path.
        app.buttons["editor.value.temp"].tap()
        let minField = app.textFields["editor.min.temp"]
        XCTAssertTrue(minField.waitForExistence(timeout: 5))
        XCTAssertEqual(minField.value as? String, "15", "the preset min prefills the field")
        minField.tap()
        minField.typeText("\n")
        let moon = app.buttons["metric.moon"]
        scrollTo(moon, in: app)
        moon.tap()
        XCTAssertTrue(next.isEnabled, "two picks, the presets parse — zero typing")
        XCTAssertFalse(app.staticTexts["editor.metricsGate"].exists, "the hint goes once the gate is met")
        next.tap()

        // Priority: Next stays off until one tile is pressed.
        let priority = app.buttons["editor.priority.temp"]
        XCTAssertTrue(priority.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled, "Press at least one.")
        XCTAssertTrue(app.staticTexts["editor.priorityGate"].exists)
        priority.tap()
        XCTAssertTrue(priority.isSelected)
        XCTAssertTrue(next.isEnabled)
        next.tap()

        // Range: both wheels; an untouched prefill takes warn-then-proceed.
        XCTAssertTrue(app.pickers["editor.startHour"].waitForExistence(timeout: 5),
                      "both hour wheels render on entry")
        XCTAssertTrue(app.pickers["editor.endHour"].exists)
        XCTAssertTrue(next.isEnabled, "the warning path keeps Next enabled")
        next.tap()
        XCTAssertTrue(app.staticTexts["editor.rangeWarning"].waitForExistence(timeout: 5),
                      "first press shows the skip warning exactly once")
        next.tap()

        // Review: the reveal, then Save.
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "second press proceeds to Review")
        XCTAssertTrue(app.staticTexts["editor.reviewTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editor.reviewTitle"].label, "Activity created",
                       "not the first Activity — the seeded store already has two")
        attachScreenshot(app, named: "wizard-review-reveal")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["Padel"].waitForExistence(timeout: 5),
                      "the scratch-built card renders with its confirmed hours")
    }

    func testBackWalksTheStepsAndKeepsTheDraft() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["addActivityCard"].tap()

        let nameField = app.textFields["editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Padel")
        let icon = app.buttons["icon.figure.tennis"]
        scrollTo(icon, in: app)
        icon.tap()
        app.buttons["editor.nextStep"].tap()
        XCTAssertTrue(app.buttons["metric.temp"].waitForExistence(timeout: 5))
        app.buttons["metric.temp"].tap()

        app.buttons["editor.back"].tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Back returns to the Name step")
        XCTAssertEqual(nameField.value as? String, "Padel", "the draft survives the walk back")
        app.buttons["editor.nextStep"].tap()
        XCTAssertTrue(app.buttons["metric.temp"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["metric.temp"].isSelected, "the pick survives too")
        app.buttons["editor.cancel"].tap()
    }

    func testMetricTileOpensAndThePriorityStepPresses() {
        // Owner rulings 2026-11-11: "Show only" is gone — Metrics picks what
        // shows, the Priority step presses what matters most.
        let app = launchApp()
        openEditorFromDetail("cycling", in: app)

        // Edit metrics lands on Metrics with the first numeric pick open.
        let temp = app.buttons["metric.temp"]
        XCTAssertTrue(temp.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.value.temp"].exists, "the opened tile shows its slider")
        XCTAssertFalse(app.buttons["editor.showOnly.temp"].exists, "no Show only anywhere")

        temp.tap()
        XCTAssertFalse(app.buttons["editor.value.temp"].exists, "tapping the open card's header unpicks it")
        temp.tap()
        XCTAssertTrue(app.buttons["editor.value.temp"].waitForExistence(timeout: 5),
                      "picking it again re-creates the preset and opens it")

        app.buttons["editor.nextStep"].tap()
        let tempPriority = app.buttons["editor.priority.temp"]
        let rainPriority = app.buttons["editor.priority.rainFall"]
        XCTAssertTrue(tempPriority.waitForExistence(timeout: 5))
        XCTAssertFalse(tempPriority.isSelected, "a fresh pick is not prioritised")
        XCTAssertTrue(rainPriority.isSelected, "Cycling's required rain threshold arrives pressed")
        XCTAssertTrue(app.staticTexts["editor.priorityExplainer"].exists)
        tempPriority.tap()
        XCTAssertTrue(tempPriority.isSelected)
        attachScreenshot(app, named: "wizard-priority")
        app.buttons["editor.cancel"].tap()
    }

    /// The owner's by-eye check of the Lane A screens (owner rulings
    /// 2026-11-11): every wizard step, the Review reveal, the opening and the
    /// dashboard, in light and in dark — screenshots only, the colours have no
    /// accessibility surface.
    func testLaneAScreensLightAndDark() {
        for appearance in ["light", "dark"] {
            let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                            "UITEST_LOCATION", "UITEST_APPEARANCE=\(appearance)",
                                            "UITEST_HOLD_OPENING"],
                                skipOpening: false)
            let splash = app.descendants(matching: .any)["opening.splash"]
            XCTAssertTrue(splash.waitForExistence(timeout: 5))
            // Held on its end frame (UITEST_HOLD_OPENING): circles + name.
            Thread.sleep(forTimeInterval: 6.5) // +1 s first-frame hold (POLISH item 5)
            XCTAssertTrue(splash.exists, "the held opening waits for a tap")
            attachScreenshot(app, named: "laneA-opening-\(appearance)")
            splash.tap()
            XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 8))
            attachScreenshot(app, named: "laneA-dashboard-\(appearance)")

            app.swipeUp()
            app.buttons["addActivityCard"].tap()
            let name = app.textFields["editor.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText("Padel\n")
            let icon = app.buttons["icon.figure.tennis"]
            scrollTo(icon, in: app)
            icon.tap()
            Thread.sleep(forTimeInterval: 1) // springs settle
            attachScreenshot(app, named: "laneA-wizard-1-name-\(appearance)")
            app.buttons["editor.nextStep"].tap()
            XCTAssertTrue(app.buttons["metric.temp"].waitForExistence(timeout: 5))
            app.buttons["metric.temp"].tap()
            app.buttons["metric.windSpeed"].tap()
            app.buttons["metric.temp"].tap()
            Thread.sleep(forTimeInterval: 1) // springs settle
            attachScreenshot(app, named: "laneA-wizard-2-metrics-\(appearance)")
            app.buttons["editor.nextStep"].tap()
            XCTAssertTrue(app.buttons["editor.priority.temp"].waitForExistence(timeout: 5))
            app.buttons["editor.priority.temp"].tap()
            Thread.sleep(forTimeInterval: 1) // springs settle
            attachScreenshot(app, named: "laneA-wizard-3-priority-\(appearance)")
            app.buttons["editor.nextStep"].tap()
            XCTAssertTrue(app.pickers["editor.startHour"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 1) // springs settle
            attachScreenshot(app, named: "laneA-wizard-4-range-\(appearance)")
            app.buttons["editor.nextStep"].tap()
            app.buttons["editor.nextStep"].tap()
            XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 5))
            sleep(2) // the reveal settles
            attachScreenshot(app, named: "laneA-wizard-5-review-\(appearance)")
            app.terminate()
        }
    }

    func testOpeningSequencePlaysOnColdLaunchAndATapSkipsIt() {
        let app = launchApp(skipOpening: false)
        let splash = app.descendants(matching: .any)["opening.splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 5), "a cold launch opens on the logo")
        attachScreenshot(app, named: "opening-splash")
        splash.tap()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5),
                      "a tap hands over to the dashboard")
        XCTAssertTrue(splash.waitForNonExistence(timeout: 5))
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

        goBackToName(in: app)
        let nameField = app.textFields["editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Cycling", "edit mode pre-fills the existing Activity")

        nameField.tap()
        nameField.typeText(" Pro")
        // Edit mode: everything is pre-filled and the window exists — every
        // step passes its gate, so Next walks straight to Review.
        advanceToReview(in: app)
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // Owner ruling 2026-11-11: Review reveals the real dashboard card.
        XCTAssertTrue(app.descendants(matching: .any)["editor.reviewCard"].exists,
                      "the Review step shows the dashboard card")
        save.tap()

        // Back from the detail to the dashboard card.
        XCTAssertTrue(app.buttons["editor.save"].waitForNonExistence(timeout: 5), "the sheet closes")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5), "back on the dashboard")
        XCTAssertTrue(app.staticTexts["Cycling Pro"].waitForExistence(timeout: 5), "the card reflects the edit after refetch")
    }

    // MARK: - Build 10 (lane MANAGE): long-press menu, detail delete, gates

    /// Long-press a card → the system context menu (owner ruling 2026-11-11,
    /// superseding the 2026-10-06 "no long press"): View details opens the
    /// detail, Move ▸ Move Down reorders, Delete asks first — and none of it
    /// refetches (the launch fetch stays the only one).
    func testCardLongPressMenuViewsMovesAndDeletesWithoutARefetch() {
        let app = launchApp()
        let cycling = app.buttons["card.cycling"]
        let fishing = app.buttons["card.fishing-lite"]
        XCTAssertTrue(cycling.waitForExistence(timeout: 5))
        let fetchCount = app.descendants(matching: .any)["uitest.fetchCount"]
        XCTAssertTrue(waitForSwitchValue(fetchCount, "1"))

        cycling.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["View details"].waitForExistence(timeout: 5), "the menu is up")
        XCTAssertTrue(app.buttons["Move"].exists)
        XCTAssertTrue(app.buttons["Delete"].exists)
        attachScreenshot(app, named: "manage-card-menu")
        app.buttons["View details"].tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5), "View details opens the detail")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()

        XCTAssertTrue(cycling.waitForExistence(timeout: 5))
        XCTAssertLessThan(cycling.frame.minY, fishing.frame.minY, "seeded order: Cycling first")
        cycling.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Move"].waitForExistence(timeout: 5))
        app.buttons["Move"].tap()
        XCTAssertTrue(app.buttons["Move Down"].waitForExistence(timeout: 5))
        app.buttons["Move Down"].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { cycling.frame.minY > fishing.frame.minY },
                      "Move Down puts Cycling under Fishing")

        fishing.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        let confirm = app.buttons["card.confirmDelete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete asks first")
        confirm.tap()
        XCTAssertTrue(fishing.waitForNonExistence(timeout: 5), "the deleted card is gone")
        XCTAssertTrue(cycling.exists)
        XCTAssertEqual(fetchCount.value as? String, "1", "reorder and delete never refetch")
    }

    /// Delete from the detail: the editor's words, confirmed, then home. The
    /// add-metric tile sits last in the grid and opens the wizard on Metrics.
    func testDetailDeleteConfirmsThenPopsHome() {
        let app = launchApp()
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        tapCardBody(card)

        let addMetric = app.buttons["detail.addMetric"]
        scrollTo(addMetric, in: app)
        XCTAssertTrue(addMetric.waitForExistence(timeout: 5), "the add-metric tile ends the grid")
        addMetric.tap()
        XCTAssertTrue(app.buttons["metric.temp"].waitForExistence(timeout: 5), "it opens the wizard on Metrics")
        app.buttons["editor.cancel"].tap()

        let delete = app.buttons["detail.delete"]
        scrollTo(delete, in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["detail.confirmDelete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete asks first")
        attachScreenshot(app, named: "manage-detail-delete-confirm")
        confirm.tap()

        XCTAssertTrue(app.buttons["card.fishing-lite"].waitForExistence(timeout: 5), "back on the dashboard")
        XCTAssertFalse(app.buttons["card.cycling"].exists, "the deleted card is gone")
    }

    /// The two-metric minimum (owner ruling 2026-11-11): one pick keeps Next
    /// off with the hint under the grid; the second turns it on.
    func testMetricsStepNeedsTwoMetrics() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["addActivityCard"].tap()
        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Padel\n")
        let icon = app.buttons["icon.figure.tennis"]
        scrollTo(icon, in: app)
        icon.tap()
        let next = app.buttons["editor.nextStep"]
        next.tap()

        XCTAssertTrue(app.buttons["metric.temp"].waitForExistence(timeout: 5))
        let hint = app.staticTexts["editor.metricsGate"]
        XCTAssertTrue(hint.exists, "the hint shows before the gate is met")
        XCTAssertEqual(hint.label, "Pick at least two")
        app.buttons["metric.temp"].tap()
        XCTAssertFalse(next.isEnabled, "one metric keeps Next off")
        XCTAssertTrue(hint.exists)
        let wind = app.buttons["metric.windSpeed"]
        scrollTo(wind, in: app)
        wind.tap()
        XCTAssertTrue(next.isEnabled, "two metrics turn Next on")
        XCTAssertFalse(hint.exists, "the hint goes once the gate is met")
        app.buttons["editor.cancel"].tap()
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    func testDeletingLastActivityLandsTheAddHeroNotADeadEnd() {
        let app = launchApp()
        openEditorFromDetail("cycling", in: app)
        // Delete lives on the Review step — edit mode walks there with Next.
        advanceToReview(in: app)
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
        advanceToReview(in: app)
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
        advanceToReview(in: app)
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

    /// Note 4: the search field is focused on open (no extra tap) and every
    /// result the geocoder returns is listed — not just the first.
    func testCityPickerFocusesSearchAndListsEveryResult() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["settingsGear"].waitForExistence(timeout: 5))
        app.buttons["settingsGear"].tap()
        let setHome = app.buttons["settings.setHome"]
        XCTAssertTrue(setHome.waitForExistence(timeout: 5))
        setHome.tap()

        let search = app.textFields["cityPicker.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: focused, evaluatedWith: search)], timeout: 5),
                       .completed, "the search field is focused on open")
        search.typeText("Springfield")

        XCTAssertTrue(app.buttons["cityPicker.result.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cityPicker.result.1"].exists, "the second result is listed too")
    }

    /// Notes 3 + 8: with location denied, Settings never claims "Using
    /// current location", and "Use current location" can't wipe a picked
    /// city it could not replace.
    func testSettingsHomeRowIsHonestWhenLocationIsDenied() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION_DENIED"])
        XCTAssertTrue(app.buttons["settingsGear"].waitForExistence(timeout: 5))
        app.buttons["settingsGear"].tap()

        XCTAssertTrue(app.staticTexts["Location off"].waitForExistence(timeout: 5),
                      "denied + no city reads the truth")
        XCTAssertFalse(app.staticTexts["Using current location"].exists)

        app.buttons["settings.setHome"].tap()
        pickCity("Dubai Marina", in: app)
        XCTAssertTrue(app.staticTexts["Dubai Marina"].waitForExistence(timeout: 5))

        let useCurrent = app.buttons["settings.useCurrentLocation"]
        XCTAssertTrue(useCurrent.exists)
        XCTAssertFalse(useCurrent.isEnabled, "no current location to fall back on while denied")
        useCurrent.tap()
        XCTAssertTrue(app.staticTexts["Dubai Marina"].exists, "the picked city survives the tap")
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
        // Note 13: one grayed placeholder per authored activity, named — the
        // seed has two, so exactly two, each carrying its activity's name.
        XCTAssertTrue(app.otherElements["skeletonCard.cycling"].exists, "grayed skeleton cards render (spec §2)")
        XCTAssertTrue(app.otherElements["skeletonCard.fishing-lite"].exists)
        XCTAssertEqual(app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'skeletonCard.'")).count, 2)
        XCTAssertEqual(app.otherElements["skeletonCard.cycling"].label, "Cycling")
        XCTAssertEqual(app.otherElements["skeletonCard.fishing-lite"].label, "Fishing Lite")
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
        tapCardBody(card)
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))

        app.buttons["detail.editRange"].tap()
        XCTAssertTrue(app.pickers["editor.startHour"].waitForExistence(timeout: 5),
                      "Edit range opens straight onto the Range step")
        XCTAssertFalse(app.textFields["editor.name"].exists, "not the Name & Icon tab")
        app.buttons["editor.cancel"].tap()

        XCTAssertTrue(app.buttons["detail.editMetrics"].waitForExistence(timeout: 5))
        app.buttons["detail.editMetrics"].tap()
        XCTAssertTrue(app.buttons["metric.temp"].waitForExistence(timeout: 5),
                      "Edit metrics opens straight onto the Metrics step")
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
        tapCardBody(card)
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
        tapCardBody(card)
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
        tapCardBody(card)
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
        tapCardBody(card)
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
    /// mock is fetched exactly once more (read off the DEBUG-only
    /// `uitest.fetchCount` probe) and the cards stay rendered through and
    /// after the pull. Launch fetches once: the location fix's reload and
    /// the foreground return are served from the 3 h forecast cache (lane
    /// CACHE — they fetched a second time before it), while the pull always
    /// bypasses it.
    func testDashboardPullToRefreshKeepsTheListRendered() {
        let app = launchApp()
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let fetchCount = app.descendants(matching: .any)["uitest.fetchCount"]
        XCTAssertTrue(fetchCount.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSwitchValue(fetchCount, "1"), "launch fetches once, got \(String(describing: fetchCount.value))")
        // Nothing else fetches while the dashboard rests.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(fetchCount.value as? String, "1", "the count has settled before the pull")
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: 320)))
        XCTAssertTrue(waitForSwitchValue(fetchCount, "2"),
                      "the pull refetches, got \(String(describing: fetchCount.value))")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the list is still rendered after the pull")
        XCTAssertTrue(app.buttons["card.fishing-lite"].exists)
        XCTAssertFalse(app.staticTexts["Checking conditions…"].exists,
                       "a pull never swaps the list for the full-screen spinner")
        tapCardBody(card)
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5),
                      "the refreshed list is live")
    }

    /// Lane CACHE, owner rule 4: the dashboard says how old its forecast is
    /// — the fetch instant on the device clock (the mock pins the clock to
    /// 00:30Z and the device zone to Dubai, +4 → 4:30).
    func testDashboardShowsTheForecastAge() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        let updated = app.buttons["forecastUpdated"]
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        XCTAssertEqual(updated.label, "Updated 4:30")
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

        tapCardBody(card)
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

    // MARK: - Dynamic Type (owner rulings 8 / 9a / 5, build 8)

    /// The largest size the pass is walked at: the hero stacks (ring on top,
    /// the hour row block under it), the grid is one column, and nothing on
    /// the dashboard or the detail runs past the screen's edges. The full
    /// walk — + → Score → return → back — must still work.
    func testAccessibilityXXLStacksTheHeroAndNothingOverflows() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION",
                                        "UITEST_APPEARANCE=light"],
                            contentSize: .accessibilityExtraExtraLarge)
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.isHittable)
        // The header's words stop at xxxLarge (note 36, POLISH item 6): the
        // 11pt location label grows past its default ~13pt line but never
        // to an accessibility size. The text size reaching the app is
        // checked on the detail's range line below.
        let location = app.staticTexts["headerLocation"]
        XCTAssertTrue(location.exists)
        XCTAssertGreaterThan(location.frame.height, 16, "the header still scales up to its cap")
        XCTAssertLessThan(location.frame.height, 30, "the header stops at xxxLarge")
        XCTAssertTrue(app.staticTexts["headerTime"].exists)
        XCTAssertTrue(app.buttons["settingsGear"].isHittable)
        assertNothingOverflowsHorizontally(app)
        attachScreenshot(app, named: "dashboard-ax-xxl")

        tapCardBody(card)
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))
        let score = app.otherElements["detail.score"]
        let row = app.descendants(matching: .any)["detail.hourStrip"]
        let line = app.staticTexts["detail.rangeLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 3))
        // The launch argument took effect: the 13pt range line is far
        // taller than its default ~16pt line.
        XCTAssertGreaterThan(line.frame.height, 30, "the text size reached the app")
        XCTAssertTrue(score.exists)
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(line.isHittable)
        XCTAssertTrue(app.buttons["detail.stepForward"].isHittable)
        // Ruling 5: the hour row drops UNDER the ring column.
        XCTAssertGreaterThanOrEqual(row.frame.minY, score.frame.maxY - 0.5,
                                    "the hero stacks: the row block sits under the ring")
        let tempCard = app.otherElements["detail.metric.temp"]
        XCTAssertTrue(tempCard.exists)
        // One column: the card is its content's height, not a full-width
        // square with an empty gap above the gauge.
        XCTAssertLessThan(tempCard.frame.height, tempCard.frame.width * 0.9,
                          "single-column metric card is intrinsic: \(tempCard.frame)")
        Thread.sleep(forTimeInterval: 0.6)
        assertNothingOverflowsHorizontally(app)
        attachScreenshot(app, named: "detail-ax-xxl")

        app.buttons["detail.stepForward"].tap()
        XCTAssertTrue(waitForLabel(row, "Hours 7am to 11am"), "got \(row.label)")
        let scoreButton = app.buttons["detail.scoreSpan"]
        XCTAssertTrue(scoreButton.waitForExistence(timeout: 2))
        XCTAssertTrue(scoreButton.isHittable)
        scoreButton.tap()
        let scored = app.staticTexts["detail.scoredSpan"]
        XCTAssertTrue(scored.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLabel(score, "Good, score 67 out of 100 for 7 to 11am"), "got \(score.label)")
        Thread.sleep(forTimeInterval: 0.6)
        assertNothingOverflowsHorizontally(app)

        let returnControl = app.buttons["detail.returnToRange"]
        XCTAssertTrue(returnControl.isHittable)
        returnControl.tap()
        XCTAssertTrue(waitForLabel(row, "Hours 6am to 10am"), "got \(row.label)")
        XCTAssertTrue(scored.waitForNonExistence(timeout: 2))

        // The edit circles keep 44pt and stay reachable below the grid.
        let editRange = app.buttons["detail.editRange"]
        scrollTo(editRange, in: app)
        XCTAssertTrue(editRange.isHittable)
        XCTAssertTrue(app.buttons["detail.editMetrics"].isHittable)
        assertNothingOverflowsHorizontally(app)

        app.navigationBars["Cycling"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5), "back returns to the dashboard")
    }

    /// The smallest size: the hero keeps its side-by-side layout and the
    /// text shrinks from the Figma defaults.
    func testExtraSmallKeepsTheSideBySideHero() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION",
                                        "UITEST_APPEARANCE=light"],
                            contentSize: .extraSmall)
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        tapCardBody(card)
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))
        let score = app.otherElements["detail.score"]
        let row = app.descendants(matching: .any)["detail.hourStrip"]
        let line = app.staticTexts["detail.rangeLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 3))
        // The launch argument took effect: the 13pt footnote line shrinks
        // (12pt at extra small — a line under the default ~15.5pt).
        XCTAssertLessThan(line.frame.height, 15.2, "the text size reached the app")
        XCTAssertLessThan(row.frame.minY, score.frame.maxY, "side by side: the row sits beside the ring")
        XCTAssertGreaterThan(row.frame.minX, score.frame.maxX, "the row is right of the ring column")
        assertNothingOverflowsHorizontally(app)
        Thread.sleep(forTimeInterval: 0.6)
        attachScreenshot(app, named: "detail-xs")
    }

    /// Every on-screen text, button and metric card stays inside the
    /// screen's width (0.5pt tolerance).
    private func assertNothingOverflowsHorizontally(_ app: XCUIApplication,
                                                    file: StaticString = #filePath, line: UInt = #line) {
        let width = app.windows.firstMatch.frame.width
        let queries: [XCUIElementQuery] = [
            app.staticTexts,
            app.buttons,
            app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.'")),
        ]
        for query in queries {
            for element in query.allElementsBoundByIndex where element.exists {
                let frame = element.frame
                guard !frame.isEmpty else { continue }
                XCTAssertGreaterThanOrEqual(frame.minX, -0.5,
                                            "\(element.identifier) '\(element.label)' runs off the left edge: \(frame)",
                                            file: file, line: line)
                XCTAssertLessThanOrEqual(frame.maxX, width + 0.5,
                                         "\(element.identifier) '\(element.label)' runs off the right edge: \(frame)",
                                         file: file, line: line)
            }
        }
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

    /// Note 27 regression guard: a plain TAP on the switch — not a slide of
    /// the knob, not XCUI's element tap — runs the opt-in. Coordinate taps on
    /// the track (left half) and the knob (right half) both land it ON. This
    /// passed before any change (the tester's taps were simulator mouse
    /// clicks); the hardware check stays owed.
    func testNotificationsSwitchFlipsOnAPlainTapOnTrackOrKnob() {
        for dx in [0.3, 0.75] {
            let app = launchApp()
            XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
            app.buttons["settingsGear"].tap()
            let row = app.switches["settings.notifications"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let knob = row.switches.firstMatch.exists ? row.switches.firstMatch : row
            knob.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
            XCTAssertTrue(waitForSwitchValue(row, "1"), "a tap at \(dx) of the switch turns it on")
            app.terminate()
        }
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

    func testPushCalloutFoldsToTheBellAndTheBellReopensIt() {
        var app = launchApp()

        let dismiss = app.buttons["pushCallout.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "first sight is the full callout")
        dismiss.tap()
        // The callout folds on the 0.35s reveal spring, so within a second.
        XCTAssertTrue(app.buttons["pushCallout"].waitForNonExistence(timeout: 1),
                      "the ✕ folds the callout away")
        let bell = app.buttons["pushCallout.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 2), "it rests as the glass bell")
        XCTAssertEqual(bell.label, "Get a morning digest + Perfect window alerts",
                       "VoiceOver hears the whole offer from the bell")

        // Relaunch WITHOUT UITEST_RESET: the resting state is remembered.
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_SEED_LIVE", "UITEST_LOCATION"])
        XCTAssertTrue(app.buttons["pushCallout.bell"].waitForExistence(timeout: 5), "still resting")
        XCTAssertFalse(app.buttons["pushCallout"].exists)

        // Tapping the bell reopens it, every time.
        for _ in 0..<2 {
            app.buttons["pushCallout.bell"].tap()
            XCTAssertTrue(app.buttons["pushCallout"].waitForExistence(timeout: 2), "the bell reveals the callout")
            app.buttons["pushCallout.dismiss"].tap()
            XCTAssertTrue(app.buttons["pushCallout.bell"].waitForExistence(timeout: 2), "and ✕ folds it back")
        }
    }

    func testDontShowAgainRemovesTheBellForGood() {
        var app = launchApp()

        let dismiss = app.buttons["pushCallout.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()
        let bell = app.buttons["pushCallout.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 2))

        bell.press(forDuration: 1.0)
        let dontShow = app.buttons["Don't show again"]
        XCTAssertTrue(dontShow.waitForExistence(timeout: 3), "long-press offers the way out")
        dontShow.tap()
        XCTAssertTrue(bell.waitForNonExistence(timeout: 2), "the bell is gone")

        // Relaunch WITHOUT UITEST_RESET — gone for good.
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_SEED_LIVE", "UITEST_LOCATION"])
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pushCallout"].exists, "no callout")
        XCTAssertFalse(app.buttons["pushCallout.bell"].exists, "and no bell")
    }

    // MARK: - Lane B screen tour (evidence shots for the owner page)

    func testLaneBScreenTourLight() { laneBScreenTour(appearance: "light") }
    func testLaneBScreenTourDark() { laneBScreenTour(appearance: "dark") }

    /// Walks the Lane B states that need taps and attaches a screenshot of
    /// each: first-sight callout, resting bell, its long-press menu, the ⓘ
    /// menu, the liked sheet, Settings with the compact Appearance segment.
    private func laneBScreenTour(appearance: String) {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION", "UITEST_BETA",
                                        "UITEST_NOW=2026-06-19T05:00:00Z",
                                        "UITEST_APPEARANCE=\(appearance)"])
        XCTAssertTrue(app.buttons["pushCallout.dismiss"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "laneB-\(appearance)-1-first-sight")

        app.buttons["pushCallout.dismiss"].tap()
        let bell = app.buttons["pushCallout.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 2))
        sleep(1)
        attachScreenshot(app, named: "laneB-\(appearance)-2-resting-bell")

        bell.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Don't show again"].waitForExistence(timeout: 3))
        attachScreenshot(app, named: "laneB-\(appearance)-3-bell-long-press")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.buttons["Don't show again"].waitForNonExistence(timeout: 3))

        app.buttons["feedbackInfo"].tap()
        XCTAssertTrue(app.buttons["What you liked"].waitForExistence(timeout: 3))
        attachScreenshot(app, named: "laneB-\(appearance)-4-info-menu")
        for (row, shot) in [("Send a suggestion", "5-suggestion-sheet"), ("What you liked", "6-liked-sheet")] {
            if !app.buttons[row].exists { app.buttons["feedbackInfo"].tap() }
            XCTAssertTrue(app.buttons[row].waitForExistence(timeout: 3))
            app.buttons[row].tap()
            XCTAssertTrue(app.textViews["feedback.editor"].waitForExistence(timeout: 5))
            sleep(1)
            attachScreenshot(app, named: "laneB-\(appearance)-\(shot)")
            app.buttons["feedback.cancel"].tap()
            XCTAssertTrue(app.textViews["feedback.editor"].waitForNonExistence(timeout: 3))
        }

        app.buttons["settingsGear"].tap()
        XCTAssertTrue(app.segmentedControls["settings.appearance"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "laneB-\(appearance)-7-settings")
    }

    // MARK: - Lane POLISH screen tour (build 10, mini-edits lane)

    /// Note 36 / POLISH item 6: at AX-XXXL the header (location, numeral,
    /// meta line, forecast age) stays inside the top 40% of the screen, the
    /// age never overlaps the meta line, and the first card still renders.
    func testHeaderStaysInTheTopFortyPercentAtAccessibilityXXXL() {
        let app = launchApp(contentSize: .accessibilityExtraExtraExtraLarge)
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame.height
        let meta = app.staticTexts["headerTime"]
        let updated = app.buttons["forecastUpdated"]
        XCTAssertTrue(meta.exists)
        XCTAssertTrue(updated.exists)
        let headerBottom = max(meta.frame.maxY, updated.frame.maxY)
        XCTAssertLessThanOrEqual(headerBottom, screen * 0.4,
                                 "header ends at \(headerBottom) of \(screen)")
        let lowestMeta = ["headerTime", "headerTemp"].map { app.staticTexts[$0].frame.maxY }.max() ?? 0
        let metaRows = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '%'")).allElementsBoundByIndex
        let humidityBottom = metaRows.map(\.frame.maxY).filter { $0 < screen * 0.5 }.max() ?? lowestMeta
        XCTAssertGreaterThanOrEqual(updated.frame.minY, humidityBottom - 1,
                                    "the forecast age sits below the meta line, not over it")
    }

    /// Note 36, card half: at AX-XXXL the card strip's hour numerals never
    /// overprint each other ("9 10" read "910").
    func testCardStripNumeralsNeverOverlapAtAccessibilityXXXL() {
        let app = launchApp(contentSize: .accessibilityExtraExtraExtraLarge)
        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let numerals = card.staticTexts.allElementsBoundByIndex
            .filter { Int($0.label) != nil && $0.frame.width > 0 }
            .sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertGreaterThanOrEqual(numerals.count, 2, "the strip prints its end numerals")
        for (left, right) in zip(numerals, numerals.dropFirst()) {
            XCTAssertLessThanOrEqual(left.frame.maxX, right.frame.minX,
                                     "\(left.label) overlaps \(right.label): \(left.frame) vs \(right.frame)")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "fixes-item7-card-ax5"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Build-9 addendum new #8: at AX-XXXL the wizard's Next button stays on
    /// screen, tall enough for its own label, and the step's last row scrolls
    /// clear above it instead of showing through it.
    func testWizardNextStaysOnScreenAndClearOfTheListAtAccessibilityXXXL() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_LOCATION"],
                            contentSize: .accessibilityExtraExtraExtraLarge)
        let hero = app.buttons["addActivitiesButton"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        hero.tap()
        let next = app.buttons["editor.nextStep"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(next.frame), "Next is wholly on screen: \(next.frame)")
        XCTAssertGreaterThanOrEqual(next.frame.height, 60, "the capsule grows with its AX5 label")

        for _ in 0..<8 { app.swipeUp() }
        let rows = app.staticTexts.allElementsBoundByIndex
            .filter { $0.label != "Next" && $0.frame.height > 0 && $0.frame.minY < window.maxY }
        let lowest = rows.map(\.frame.maxY).max() ?? 0
        XCTAssertLessThanOrEqual(lowest, next.frame.minY + 1,
                                 "the last row ends above Next (\(lowest) vs \(next.frame.minY))")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "fixes-item9-wizard-ax5"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPolishScreenTourLight() { polishScreenTour(appearance: "light") }
    func testPolishScreenTourDark() { polishScreenTour(appearance: "dark") }

    /// The surfaces the owner rules on from screenshots: home at the default
    /// size and at AX-XXXL, the add slot after the list, and the detail page
    /// (top and scrolled to its containers).
    private func polishScreenTour(appearance: String) {
        let base = ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION",
                    "UITEST_APPEARANCE=\(appearance)"]
        var app = launchApp(arguments: base)
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "polish-\(appearance)-home")

        app.swipeUp()
        XCTAssertTrue(app.buttons["addActivityCard"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "polish-\(appearance)-add-slot")
        app.swipeDown()

        tapCardBody(app.buttons["card.cycling"])
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["detail.metric.temp"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "polish-\(appearance)-detail")
        app.swipeUp()
        sleep(1)
        attachScreenshot(app, named: "polish-\(appearance)-detail-scrolled")
        app.navigationBars["Cycling"].buttons.firstMatch.tap()

        // A detail with red / amber values on the containers.
        XCTAssertTrue(app.buttons["card.fishing-lite"].waitForExistence(timeout: 5))
        tapCardBody(app.buttons["card.fishing-lite"])
        XCTAssertTrue(app.otherElements["detail.metric.temp"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "polish-\(appearance)-detail-fishing")
        app.navigationBars.buttons.firstMatch.tap()

        // The callout folded to its resting bell: the first card at eye level.
        XCTAssertTrue(app.buttons["pushCallout.dismiss"].waitForExistence(timeout: 5))
        app.buttons["pushCallout.dismiss"].tap()
        XCTAssertTrue(app.buttons["pushCallout.bell"].waitForExistence(timeout: 3))
        sleep(1)
        attachScreenshot(app, named: "polish-\(appearance)-home-bell")
        app.terminate()

        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_LOCATION",
                                    "UITEST_APPEARANCE=\(appearance)"])
        XCTAssertTrue(app.buttons["addActivitiesButton"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "polish-\(appearance)-first-launch")
        app.terminate()

        app = launchApp(arguments: base, contentSize: .accessibilityExtraExtraExtraLarge)
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "polish-\(appearance)-home-ax-xxxl")
        app.terminate()

        app = launchApp(arguments: base, contentSize: .extraExtraExtraLarge)
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "polish-\(appearance)-home-xxxl")
    }

    // MARK: - Light / Dark — one value, two controls

    func testHeaderToggleAndSettingsSegmentShareOneAppearance() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION"])

        let toggle = app.buttons["appearanceToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the toggle mirrors the gear")
        XCTAssertGreaterThanOrEqual(toggle.frame.width, 44, "HIG target")
        let before = toggle.label
        toggle.tap()
        XCTAssertTrue(waitForLabelChange(toggle, from: before, timeout: 2),
                      "the toggle now offers the other appearance")
        let showingDark = toggle.label == "Switch to Light"

        app.buttons["settingsGear"].tap()
        let segment = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5), "Settings › Appearance")
        XCTAssertTrue(segment.buttons[showingDark ? "Dark" : "Light"].isSelected,
                      "the segment shows the same single value")
        XCTAssertFalse(segment.buttons["System"].exists, "two modes only")

        segment.buttons[showingDark ? "Light" : "Dark"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForLabel(toggle, NSPredicate(format: "label == %@", before), timeout: 3),
                      "and the header follows the segment")
    }

    private func waitForLabelChange(_ element: XCUIElement, from old: String, timeout: TimeInterval) -> Bool {
        waitForLabel(element, NSPredicate(format: "label != %@", old), timeout: timeout)
    }

    private func waitForLabel(_ element: XCUIElement, _ predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)],
                         timeout: timeout) == .completed
    }

    // MARK: - Beta feedback — the ⓘ menu + the two feedback sheets

    /// Opens the beta ⓘ menu and picks `row` ("Send a suggestion" /
    /// "What you liked").
    private func openFeedback(_ app: XCUIApplication, row: String) {
        let info = app.buttons["feedbackInfo"]
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        info.tap()
        let item = app.buttons[row]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the menu offers \(row)")
        item.tap()
    }

    func testBetaFeedbackMenuRendersWhenGateOn() {
        // Pinned Light (absent = the simulator's appearance) so the shot below
        // is the light glass: the header gear, the ⓘ circle, the add capsule.
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION", "UITEST_BETA", "UITEST_APPEARANCE=light"])

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "dashboard-glass-light")
        XCTAssertFalse(app.otherElements["betaBanner"].exists, "the disclaimer card is gone")
        let info = app.buttons["feedbackInfo"]
        XCTAssertTrue(info.exists, "the ⓘ renders on a beta (dev/TestFlight) install")
        XCTAssertGreaterThanOrEqual(info.frame.width, 44, "HIG target")
        info.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Early test build'")).firstMatch.waitForExistence(timeout: 5),
                      "the disclaimer folds into the menu's header line")
        XCTAssertTrue(app.buttons["Send a suggestion"].exists)
        XCTAssertTrue(app.buttons["What you liked"].exists)
        attachScreenshot(app, named: "feedback-menu-open")
        XCTAssertFalse(app.textViews["feedback.editor"].exists, "a first tap only opens the menu")
    }

    func testBetaFeedbackMenuAbsentWhenGateOff() {
        // No UITEST_BETA — the same archive's App Store face.
        let app = launchApp()

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feedbackInfo"].exists, "App Store installs never see beta surfaces")
    }

    func testSuggestionSheetHappyPathSendsConfirmsAndDismisses() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION", "UITEST_BETA"])

        openFeedback(app, row: "Send a suggestion")

        let editor = app.textViews["feedback.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "the sheet opens on a text editor")
        XCTAssertTrue(app.staticTexts["feedback.note"].exists, "the owner's note sits above it")
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
        XCTAssertTrue(app.buttons["feedbackInfo"].isHittable, "back on the dashboard")
    }

    func testLikedSendFailureKeepsTypedTextAndOffersRetry() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION", "UITEST_BETA", "UITEST_FEEDBACK_FAIL"])

        openFeedback(app, row: "What you liked")

        let editor = app.textViews["feedback.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Keep this text")
        app.buttons["feedback.send"].tap()

        XCTAssertTrue(app.staticTexts["feedback.error"].waitForExistence(timeout: 5),
                      "the non-204 surfaces its error")
        XCTAssertEqual(editor.value as? String, "Keep this text", "a typed note is never discarded")
        XCTAssertTrue(app.buttons["feedback.send"].isEnabled, "Send stays as the retry")
        XCTAssertFalse(app.staticTexts["feedback.success"].exists)
    }
}
