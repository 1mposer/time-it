import XCTest
@testable import TimeIt

/// Pins the header's temperature bands (Figma Header node 92:11: Cool blue /
/// Mid amber / Hot salmon) and the label's save-time capitalization.
final class HeaderBandTests: XCTestCase {

    // MARK: header band — same 33/38 breakpoints as the temp chip

    func testCoolBelow33() {
        XCTAssertEqual(Theme.HeaderBand.band(forTemp: 24), .cool)
        XCTAssertEqual(Theme.HeaderBand.band(forTemp: 32.9), .cool)
    }

    func testMidFrom33To38Exclusive() {
        XCTAssertEqual(Theme.HeaderBand.band(forTemp: 33), .mid)
        XCTAssertEqual(Theme.HeaderBand.band(forTemp: 37.9), .mid)
    }

    func testHotAt38AndUp() {
        XCTAssertEqual(Theme.HeaderBand.band(forTemp: 38), .hot,
                       "the TestFlight finding: 38°C must not render the cool header")
        XCTAssertEqual(Theme.HeaderBand.band(forTemp: 45), .hot)
    }

    func testNoReadingDefaultsToCool() {
        XCTAssertEqual(Theme.HeaderBand.band(forTemp: nil), .cool)
    }

    // MARK: label capitalization — first letter uppercased at save

    func testFinalLabelCapitalizesFirstLetter() {
        XCTAssertEqual(ActivityDraft.finalLabel("cycling"), "Cycling")
    }

    func testFinalLabelTrimsThenCapitalizes() {
        XCTAssertEqual(ActivityDraft.finalLabel("  night walk "), "Night walk")
    }

    func testFinalLabelLeavesAlreadyCapitalized() {
        XCTAssertEqual(ActivityDraft.finalLabel("Boat Fishing"), "Boat Fishing")
    }

    func testFinalLabelEmptyAndNonLetterSafe() {
        XCTAssertEqual(ActivityDraft.finalLabel("   "), "")
        XCTAssertEqual(ActivityDraft.finalLabel("5-a-side"), "5-a-side")
    }

    func testDraftResultSavesCapitalizedLabel() {
        var draft = ActivityDraft(from: Fixtures.cycling)
        draft.label = "sunset run"
        let built = draft.result(against: StaticMetricCatalog())
        XCTAssertEqual(built.activity?.label, "Sunset run")
    }
}
