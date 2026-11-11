import XCTest
@testable import TimeIt

/// Pins `HeaderView.clockText` — the dashboard clock follows the forecast
/// location's zone (a Bangkok home shows Bangkok time from Dubai), falling
/// back to the device's own zone while no forecast is loaded.
final class HeaderClockTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_750_000_000)

    func testClockFollowsTheForecastZone() {
        let bangkok = HeaderView.clockText(for: date, timezoneIdentifier: "Asia/Bangkok")
        let dubai = HeaderView.clockText(for: date, timezoneIdentifier: "Asia/Dubai")

        let expected = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
                                                       timeZone: TimeZone(identifier: "Asia/Bangkok")!))
        XCTAssertEqual(bangkok, expected)
        XCTAssertNotEqual(bangkok, dubai, "zones 3 hours apart must render different clocks")
    }

    func testMissingZoneFallsBackToTheDeviceClock() {
        let text = HeaderView.clockText(for: date, timezoneIdentifier: nil)
        XCTAssertEqual(text, date.formatted(date: .omitted, time: .shortened),
                       "no forecast yet → the device's own wall clock")
    }
}

/// Build 10 POLISH item 1: the meta line's three readings grew from the
/// 13pt footnote into the dead space above the first card.
final class HeaderMetaSizeTests: XCTestCase {
    func testTheMetaReadingsAreBodySizedNotFootnote() {
        XCTAssertEqual(HeaderView.metaFontSize, 17)
        XCTAssertEqual(Theme.Typography.textStyle(forFigmaSize: HeaderView.metaFontSize), .body,
                       "the readings scale as body text under Dynamic Type")
        XCTAssertGreaterThan(HeaderView.metaGlyphSize, 11, "the glyphs grow with the readings")
    }
}
