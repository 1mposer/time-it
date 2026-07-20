import XCTest

/// Acceptance tests for the dashboard (#5a) and the authoring layer (#5b).
/// The app is launched with a hermetic mock backend (launch arguments below)
/// so the suite is deterministic — it does not need the Node server or a
/// Meteosource key.
/// - `UITEST_MOCK_SUCCESS`: canned ForecastResponse (first activity windowed
///   today, second windowed tomorrow, the rest null).
/// - `UITEST_MOCK_FAILURE`: the API throws providerUnavailable (server down / 502).
/// - `UITEST_RESET`: wipes persisted activities + preferences so each test
///   starts from the first-launch seed state (omit it to test persistence).
final class TimeItUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(arguments: [String] = ["UITEST_MOCK_SUCCESS", "UITEST_RESET"]) -> XCUIApplication {
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

    // MARK: launch surface (#5a)

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
        // The mock fixture's hours[0] is temp 24 / wind 10 / humidity 40 — the
        // header renders the location's current-hour conditions from hours.first.
        XCTAssertTrue(app.staticTexts["24°C"].exists)
        XCTAssertTrue(app.staticTexts["10 km/h"].exists)
        XCTAssertTrue(app.staticTexts["40%"].exists)
        XCTAssertTrue(app.buttons["settingsGear"].exists, "top-right gear, not a sign-in button")
    }

    // MARK: cards (#5a)

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

    func testCardShowsDayLabelTimelineAndChips() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        // Mock: Cycling is windowed today; Fishing Lite's only window is
        // tomorrow, which the card must NOT roll forward to (ADR-0004
        // amendment 2026-07-20) — it renders the none-state instead.
        XCTAssertTrue(app.staticTexts["Today"].exists)
        XCTAssertTrue(app.staticTexts["No window today"].exists)
        XCTAssertFalse(app.staticTexts["Tomorrow"].exists,
                       "the dashboard never shows a later day — the week lives in the detail")
        XCTAssertTrue(app.otherElements["timeline.cycling"].exists)
        XCTAssertTrue(app.staticTexts["chip.cycling.temp"].exists, "at least one metric chip on the card")
    }

    // MARK: navigation (#5a)

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

    // MARK: error state (#5a)

    func testServerFailureShowsErrorState() {
        let app = launchApp(arguments: ["UITEST_MOCK_FAILURE", "UITEST_RESET"])

        XCTAssertTrue(app.staticTexts["Weather Unavailable"].waitForExistence(timeout: 5),
                      "provider failure renders the ContentUnavailableView error state")
        XCTAssertFalse(app.buttons["card.cycling"].exists)
    }

    // MARK: ghost add-card + add flow (#5b)

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

        save.tap()
        XCTAssertTrue(app.staticTexts["Padel"].waitForExistence(timeout: 5), "the scratch-built card renders")
    }

    // MARK: edit + delete via the card gear (#5b)

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

    func testDeletingActivitiesShowsEmptyStateAfterLastOne() {
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

        XCTAssertTrue(app.staticTexts["emptyStateMessage"].waitForExistence(timeout: 5),
                      "deleting the last Activity shows the empty state, no crash, no POST")
        XCTAssertTrue(app.buttons["addActivityCard"].exists, "the add-card remains the way back in")
        XCTAssertEqual(cardCount(in: app), 0)
    }

    // MARK: persistence across relaunch (#5b)

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
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS"]) // no RESET — keep the authored list

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Running"].waitForExistence(timeout: 5),
                      "the authored list (not the seeds) survives a relaunch")
    }

    // MARK: home location (#5b)

    func testHomeLocationPersistsAcrossRelaunchAndClears() {
        var app = launchApp()
        XCTAssertTrue(app.buttons["settingsGear"].waitForExistence(timeout: 5))
        app.buttons["settingsGear"].tap()

        let search = app.textFields["settings.locationSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Dubai Marina")
        app.buttons["settings.searchButton"].tap()

        let result = app.buttons["settings.result.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), "the (mock) geocoder returns a result")
        result.tap()
        XCTAssertTrue(app.staticTexts["Dubai Marina"].waitForExistence(timeout: 5), "home location is set")
        app.buttons["Done"].tap()

        app.terminate()
        app = launchApp(arguments: ["UITEST_MOCK_SUCCESS"]) // no RESET
        XCTAssertTrue(app.buttons["settingsGear"].waitForExistence(timeout: 5))
        app.buttons["settingsGear"].tap()
        XCTAssertTrue(app.staticTexts["Dubai Marina"].waitForExistence(timeout: 5), "home location survives a relaunch")

        app.buttons["settings.useCurrentLocation"].tap()
        XCTAssertTrue(app.staticTexts["Using current location"].waitForExistence(timeout: 5), "clearing returns to GPS")
    }
}
