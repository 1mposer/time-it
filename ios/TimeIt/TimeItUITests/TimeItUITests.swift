import XCTest

/// Acceptance tests for the #5a dashboard. The app is launched with a hermetic
/// mock backend (launch arguments below) so the suite is deterministic — it does
/// not need the Node server or a Meteosource key.
/// - `UITEST_MOCK_SUCCESS`: canned ForecastResponse (Cycling windowed today,
///   Fishing Lite windowed tomorrow).
/// - `UITEST_MOCK_FAILURE`: the API throws providerUnavailable (server down / 502).
final class TimeItUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(arguments: [String] = ["UITEST_MOCK_SUCCESS"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
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
        // The mock fixture's hours[0] is temp 24 / wind 10 / humidity 40 — the
        // header renders the location's current-hour conditions from hours.first.
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

    func testCardShowsDayLabelTimelineAndChips() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["card.cycling"].waitForExistence(timeout: 5))
        // Mock: Cycling is windowed today; Fishing Lite's soonest-actionable day is tomorrow.
        XCTAssertTrue(app.staticTexts["Today"].exists)
        XCTAssertTrue(app.staticTexts["Tomorrow"].exists)
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

    // MARK: error state

    func testServerFailureShowsErrorState() {
        let app = launchApp(arguments: ["UITEST_MOCK_FAILURE"])

        XCTAssertTrue(app.staticTexts["Weather Unavailable"].waitForExistence(timeout: 5),
                      "provider failure renders the ContentUnavailableView error state")
        XCTAssertFalse(app.buttons["card.cycling"].exists)
    }
}
