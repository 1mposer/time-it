import XCTest

/// Acceptance tests for the dashboard and the authoring layer. The app is
/// launched with a hermetic mock backend (launch arguments below), so the
/// suite is deterministic — no Node server or Meteosource key needed.
/// - `UITEST_MOCK_SUCCESS`: canned ForecastResponse (first activity windowed
///   today, second windowed tomorrow, the rest null).
/// - `UITEST_MOCK_FAILURE`: the API throws providerUnavailable (server down / 502).
/// - `UITEST_RESET`: wipes persisted activities + preferences (incl. the
///   last-resolved cache and the dismissals/phrases keys) so each test starts
///   from first-launch state (omit to test persistence).
/// - `UITEST_SEED_LIVE`: pre-persists the two templates as LIVE (ranges
///   confirmed) — the real first launch is dormant (no request, no rated
///   cards), so card/flow tests scaffold on this instead.
/// - `UITEST_SEED_NOCTURNAL`: pre-persists stargazing LIVE (wrapped 10pm–4am
///   range) — the nocturnal parity path (6 night buckets, "Tonight" copy).
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
final class TimeItUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(arguments: [String] = ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
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

    // MARK: launch surface

    func testLaunchesDirectlyToDashboardWithNoGateOrTabBar() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["headerTime"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0, "no bottom tab bar (grill Q8)")
        XCTAssertFalse(app.buttons["Sign In"].exists)
        XCTAssertFalse(app.staticTexts["Sign In"].exists)
    }

    func testHeaderShowsCurrentConditionsAndGear() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["headerTime"].waitForExistence(timeout: 5))
        // Mock fixture's hours[0] = temp 24 / wind 10 / humidity 40 — header
        // renders from hours.first.
        XCTAssertTrue(app.staticTexts["24°C"].exists)
        XCTAssertTrue(app.staticTexts["10 km/h"].exists)
        XCTAssertTrue(app.staticTexts["40%"].exists)
        XCTAssertTrue(app.buttons["settingsGear"].exists, "top-right gear, not a sign-in button")
    }

    // MARK: cards

    func testOneCardPerSeedTemplateInRequestOrderWithNoProBadge() {
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

    func testCardShowsSublabelTimelineChipsAndNoRatingWord() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        // Mock: Cycling is Perfect today across its 6–10am range — the
        // sublabel carries the best stretch in the push-copy dialect.
        XCTAssertTrue(app.staticTexts["Today · 6–10am"].exists)
        // Fishing Lite has nothing today (all-red range): plain "Today", the
        // always-visible all-bad phrase — its tomorrow window must NOT roll
        // forward onto the card (ADR-0004 amendment).
        XCTAssertTrue(app.staticTexts["Today"].exists)
        XCTAssertTrue(app.staticTexts["Nothing in your range"].exists)
        XCTAssertFalse(app.staticTexts["Tomorrow"].exists,
                       "the dashboard never shows a later day — the week lives in the detail")
        // The user's range as a chip, and no rating word anywhere (decision C
        // — color carries quality; words are opt-in via §5).
        let rangeChip = app.staticTexts["rangeChip.cycling"]
        XCTAssertTrue(rangeChip.exists)
        XCTAssertEqual(rangeChip.label, "Range 6 – 10am")
        XCTAssertFalse(app.staticTexts["Perfect"].exists)
        XCTAssertFalse(app.staticTexts["Good"].exists)
        XCTAssertTrue(app.otherElements["timeline.cycling"].exists)
        XCTAssertTrue(app.staticTexts["chip.cycling.temp"].exists, "at least one metric chip on the card")
    }

    // MARK: navigation

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

    // MARK: first launch is dormant — the showcase

    func testFirstLaunchShowsTheDormantShowcase() {
        // The REAL first launch (no UITEST_SEED_LIVE): the full four-template
        // catalog renders as "Set your range →" showcase cards — no request
        // is made, no rated cards.
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_LOCATION"])

        XCTAssertTrue(app.staticTexts["headerTime"].waitForExistence(timeout: 5), "the header still renders")
        XCTAssertTrue(app.otherElements["showcase.cycling"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["showcase.stargazing"].exists, "all four templates show (owner ruling 2026-08-13)")
        XCTAssertTrue(app.buttons["showcase.setRange.cycling"].exists, "the Range door is the CTA")
        XCTAssertEqual(cardCount(in: app), 0, "dormant activities never rate — no cards without a confirmed range")
        XCTAssertFalse(app.staticTexts["trueEmptyMessage"].exists,
                       "dormant is NOT the no-activities empty state — the store is seeded")
        XCTAssertFalse(app.staticTexts["Weather Unavailable"].exists, "and it is not an error — no request was made")
        // PROPOSED (owner review pending): no fetch happened, so the weather
        // rows hide rather than dangle "—".
        XCTAssertFalse(app.staticTexts["headerTemp"].exists,
                       "no fabricated or placeholder weather while nothing is live")
    }

    func testShowcaseSetYourRangeConfirmsThePrefillAndRatesTheCard() {
        // The Range step (the editor, until the wizard lands) is the only
        // door out of dormancy — confirming the prefilled range triggers the
        // first POST and the rated card replaces the showcase card.
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_LOCATION"])

        let cta = app.buttons["showcase.setRange.cycling"]
        XCTAssertTrue(cta.waitForExistence(timeout: 5))
        cta.tap()

        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the editor opens with the template prefill loaded")
        XCTAssertTrue(save.isEnabled, "a template prefill is valid as-is — saving is the confirmation")
        save.tap()

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5),
                      "the first confirmed range makes the first request and rates the card")
        XCTAssertTrue(app.otherElements["showcase.fishing-lite"].exists,
                      "the other templates stay dormant showcase cards — visible, never POSTed")
    }

    func testDismissingAShowcaseCardRemovesIt() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_LOCATION"])

        let dismiss = app.buttons["showcase.dismiss.cycling"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()

        XCTAssertTrue(app.otherElements["showcase.cycling"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["showcase.fishing-lite"].exists, "only the dismissed template goes")
        XCTAssertEqual(cardCount(in: app), 0)
    }

    func testDismissingEveryTemplateShowsTheTrueEmptyAddCTA() {
        // Standing invariant: the dashboard always offers a next action. With
        // every template dismissed the showcase cannot re-seed — the
        // true-empty state's Add CTA is the way forward.
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_LOCATION"])

        for id in ["cycling", "fishing-lite", "running", "stargazing"] {
            let dismiss = app.buttons["showcase.dismiss.\(id)"]
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "showcase card \(id) offers its ✕")
            dismiss.tap()
        }

        XCTAssertTrue(app.staticTexts["No activities"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["trueEmptyMessage"].exists)
        let add = app.buttons["addActivitiesButton"]
        XCTAssertTrue(add.exists, "the Add CTA is the standing next action — never a dead end")
        add.tap()
        XCTAssertTrue(app.buttons["addFromScratch"].waitForExistence(timeout: 5), "the CTA opens the Add flow")
    }

    // MARK: error state

    func testServerFailureShowsErrorState() {
        // UITEST_LOCATION matters here: without a resolvable location, the
        // no-location state wins and the failing API is never called — the
        // store must be seeded LIVE or no request happens at all.
        let app = launchApp(arguments: ["UITEST_MOCK_FAILURE", "UITEST_RESET", "UITEST_SEED_LIVE", "UITEST_LOCATION"])

        XCTAssertTrue(app.staticTexts["Weather Unavailable"].waitForExistence(timeout: 5),
                      "provider failure renders the ContentUnavailableView error state")
        XCTAssertFalse(app.buttons["card.cycling"].exists)
    }

    // MARK: ghost add-card + add flow

    func testGhostAddCardIsVisibleAfterCardsAndOpensAddFlow() {
        let app = launchApp()

        let addCard = app.buttons["addActivityCard"]
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(addCard.waitForExistence(timeout: 5), "ghost add-card renders after the card list")
        addCard.tap()

        XCTAssertTrue(app.buttons["addFromScratch"].waitForExistence(timeout: 5), "AddActivityView offers from-scratch")
        XCTAssertTrue(app.buttons["template.running"].exists, "and the Template catalog")
    }

    func testAddFromTemplatePrefillsEditorAndSavesNewCard() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        let before = cardCount(in: app)
        app.swipeUp()
        app.buttons["addActivityCard"].tap()

        app.buttons["template.running"].tap()
        let nameField = app.textFields["editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Running", "editor is pre-filled from the Template")

        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.isEnabled, "a Template copy is valid as-is")
        save.tap()

        XCTAssertTrue(app.staticTexts["Running"].waitForExistence(timeout: 5), "the new card renders after refetch")
        app.swipeUp()
        XCTAssertEqual(cardCount(in: app), before + 1)
    }

    func testAddFromScratchGatesSaveUntilValid() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["addActivityCard"].tap()
        app.buttons["addFromScratch"].tap()

        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "empty label + no metrics → invalid")

        let nameField = app.textFields["editor.name"]
        nameField.tap()
        nameField.typeText("Padel")
        XCTAssertFalse(save.isEnabled, "a label alone is not enough — displayMetrics must be non-empty")

        app.buttons["metric.temp"].tap()
        XCTAssertTrue(save.isEnabled, "label + one metric (no threshold) is a valid show-but-don't-judge body")

        app.swipeUp()
        app.buttons["editor.addThreshold.temp"].tap()
        XCTAssertFalse(save.isEnabled, "a bound-less numeric threshold is a hard 400 — Save must lock")

        let minField = app.textFields["editor.min.temp"]
        minField.tap()
        minField.typeText("15")
        XCTAssertTrue(save.isEnabled, "one bound satisfies the numeric threshold rule")

        // The "Only at certain hours" toggle is DELETED — the Range section
        // always shows its pickers (prefilled 6–10am from scratch); saving
        // confirms the range. No whole-day path exists.
        XCTAssertFalse(app.switches["editor.windowToggle"].exists,
                       "the window toggle is gone — ranges are mandatory")
        scrollTo(app.buttons["editor.startHour"], in: app)
        XCTAssertTrue(app.buttons["editor.startHour"].exists, "the Range pickers are always present")

        save.tap()
        XCTAssertTrue(app.staticTexts["Padel"].waitForExistence(timeout: 5),
                      "the scratch-built card renders with its confirmed range")
    }

    // MARK: edit + delete via the card gear

    func testGearOpensEditorAndEditedLabelReflectsOnCard() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))

        app.buttons["gear.cycling"].tap()
        let nameField = app.textFields["editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Cycling", "edit mode pre-fills the existing Activity")

        nameField.tap()
        nameField.typeText(" Pro")
        app.buttons["editor.save"].tap()

        XCTAssertTrue(app.staticTexts["Cycling Pro"].waitForExistence(timeout: 5), "the card reflects the edit after refetch")
    }

    func testDeletingLastActivityReseedsDormantShowcaseNotEmptyState() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))

        app.buttons["gear.cycling"].tap()
        XCTAssertTrue(app.textFields["editor.name"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["editor.delete"], in: app)
        XCTAssertTrue(app.buttons["editor.delete"].waitForExistence(timeout: 5))
        app.buttons["editor.delete"].tap()
        // confirmationDialog buttons surface twice in the hierarchy — firstMatch disambiguates
        XCTAssertTrue(app.buttons["editor.confirmDelete"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["editor.confirmDelete"].firstMatch.tap()

        XCTAssertTrue(app.buttons["card.fishing-lite"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["card.cycling"].exists, "deleted card is gone")

        app.buttons["gear.fishing-lite"].tap()
        XCTAssertTrue(app.textFields["editor.name"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["editor.delete"], in: app)
        XCTAssertTrue(app.buttons["editor.delete"].waitForExistence(timeout: 5))
        app.buttons["editor.delete"].tap()
        // confirmationDialog buttons surface twice in the hierarchy — firstMatch disambiguates
        XCTAssertTrue(app.buttons["editor.confirmDelete"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["editor.confirmDelete"].firstMatch.tap()

        // Deleting the last Activity re-seeds the showcase DORMANT — the
        // four "Set your range →" cards render (no rated cards, no request),
        // NOT the no-activities empty state.
        XCTAssertTrue(app.buttons["card.fishing-lite"].waitForNonExistence(timeout: 5),
                      "no rated cards — the re-seeded showcase is dormant")
        XCTAssertTrue(app.otherElements["showcase.cycling"].waitForExistence(timeout: 5),
                      "the non-dismissed templates come back as showcase cards")
        XCTAssertEqual(cardCount(in: app), 0)
        XCTAssertFalse(app.staticTexts["trueEmptyMessage"].exists,
                       "the re-seeded showcase is not the empty state — deleting everything is not a dead end")
    }

    // MARK: persistence across relaunch

    func testAuthoredListPersistsAcrossRelaunch() {
        var app = launchApp()
        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["addActivityCard"].tap()
        app.buttons["template.running"].tap()
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 5))
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.staticTexts["Running"].waitForExistence(timeout: 5))

        app.terminate()
        // No RESET and no SEED_LIVE — the persisted authored list must feed
        // the relaunch on its own.
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_LOCATION"])

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Running"].waitForExistence(timeout: 5),
                      "the authored list (not the seeds) survives a relaunch")
    }

    // MARK: home location

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

    // MARK: no-location onboarding

    func testNoLocationShowsSkeletonsAndCTAsWithNoWeather() {
        // No UITEST_LOCATION: the provider never resolves. Seeded LIVE
        // because the all-dormant showcase is the first-launch screen —
        // no-location surfaces once a confirmed range makes a fetch worth
        // attempting.
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
        // A TRUE fresh install now shows the dormant showcase (location not
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

    // MARK: phrases toggle

    func testPhrasesToggleDefaultOffAndShowsPhraseWhenEnabled() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Perfect throughout"].exists,
                       "default OFF — a rated card shows no words (§2); color carries quality")

        app.buttons["settingsGear"].tap()
        let toggle = app.switches["settings.showPhrases"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the DASHBOARD row exists")
        XCTAssertEqual(toggle.value as? String, "0", "the phrases row defaults off")
        // The identifier sits on the whole Toggle row — tap the nested switch.
        let control = toggle.switches.firstMatch
        (control.exists ? control : toggle).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["Done"].tap()

        // Cycling's 6–10am range is all-green in the mock → (green, green)
        // with no interior escape reduces to "Perfect throughout".
        XCTAssertTrue(app.staticTexts["Perfect throughout"].waitForExistence(timeout: 5),
                      "with the toggle on, the card shows its trajectory phrase")
    }

    // MARK: detail page

    func testDetailShowsRangeOnceSetupOnceAlignedWeekAndTapToExpand() {
        let app = launchApp()

        let card = app.buttons["card.cycling"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.navigationBars["Cycling"].waitForExistence(timeout: 5))

        // The Range stated once, with its edit door.
        XCTAssertTrue(app.staticTexts["Your window: 6 – 10am daily"].exists)
        XCTAssertTrue(app.buttons["detail.editRange"].exists)
        // The setup stated once (never repeated per hour).
        XCTAssertTrue(app.staticTexts["Temp 15 – 32°C required · Wind ≤ 25 km/h optional · Rain ≤ 0.2 mm required · UV ≤ 8 optional"].exists)
        XCTAssertTrue(app.buttons["detail.editMetrics"].exists)
        // 7 aligned day rows (diurnal), best-stretch time on rated days.
        XCTAssertTrue(app.staticTexts["Today"].exists)
        XCTAssertTrue(app.staticTexts["6–10am"].exists, "Today's best stretch")

        // Hourly numbers only behind a tap, collapsed by default (expanded
        // while Today is still on screen, before scrolling).
        XCTAssertFalse(app.otherElements["detail.hours.0"].exists, "collapsed by default")
        app.buttons["detail.day.0"].tap()
        XCTAssertTrue(app.otherElements["detail.hours.0"].waitForExistence(timeout: 5),
                      "the tapped day reveals its range hours")

        // The week runs to Thursday (7 rows) and shares the range-zoomed axis
        // once under the stack. Rows beyond the first are read via VoiceOver
        // labels (XCUI flattens button inner texts).
        let dayRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.day.'"))
        XCTAssertEqual(dayRows.count, 7, "7 aligned day rows for a diurnal activity")
        XCTAssertTrue(app.buttons["detail.day.6"].label.hasPrefix("Thursday"),
                      "the week runs Today through Thursday")
        XCTAssertTrue(app.staticTexts["8am"].exists, "the shared range axis midpoint")
    }

    func testNocturnalDetailShowsSixNightRowsAndNightlyHeader() {
        // Nocturnal parity: same skeleton, night-phrased — 6 night buckets
        // (per-activity days.length), evening-keyed rows, range-zoomed
        // 10pm/1am/4am axis.
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_NOCTURNAL", "UITEST_LOCATION"])

        let card = app.buttons["card.stargazing"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tonight · 10pm–2am"].exists, "the nocturnal sublabel says Tonight")
        card.tap()
        XCTAssertTrue(app.navigationBars["Stargazing"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Your window: 10pm – 4am nightly"].exists)
        // Day rows read via their VoiceOver labels — XCUI flattens a SwiftUI
        // button's inner texts, so the label (day name + rating + times, the
        // spoken-summary dialect) is the deterministic surface.
        let dayRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'detail.day.'"))
        XCTAssertEqual(dayRows.count, 6, "a nocturnal activity has 6 night buckets, never an assumed 7")
        XCTAssertTrue(app.buttons["detail.day.0"].label.hasPrefix("Tonight"),
                      "night rows are evening-keyed — bucket 0 is Tonight")
        XCTAssertTrue(app.buttons["detail.day.1"].label.hasPrefix("Tomorrow night"))
        XCTAssertTrue(app.staticTexts["1am"].exists, "the range-zoomed axis midpoint crosses midnight")
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

    // MARK: push opt-in client

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

    // MARK: beta feedback — disclaimer banner + suggestion sheet

    func testBetaBannerAndSuggestionButtonRenderWhenGateOn() {
        let app = launchApp(arguments: ["UITEST_MOCK_SUCCESS", "UITEST_RESET", "UITEST_SEED_LIVE",
                                        "UITEST_LOCATION", "UITEST_BETA"])

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
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
}
