import XCTest
@testable import TimeIt

/// Pins the Settings copy the fresh-eyes pass ruled (spec row 2a, owner
/// 2026-11-12): the Notifications footer says what arrives and when, and the
/// city picker opened from the switch says why it opened.
final class SettingsCopyTests: XCTestCase {

    func testNotificationsFooterNamesDigestAndAlert() {
        XCTAssertEqual(SettingsCopy.notificationsFooter,
                       "A morning summary of your best hours, and an alert when a Perfect window opens.")
    }

    func testCityPickerFromSwitchShowsReason() {
        XCTAssertEqual(CityPickerReason.notifications.headline,
                       "Pick a city so alerts know where to look.")
    }

    func testCityPickerOpenedElsewhereShowsNoReason() {
        XCTAssertNil(CityPickerReason.headline(for: nil),
                     "the dashboard CTA and Set home location open the picker without a reason line")
        XCTAssertEqual(CityPickerReason.headline(for: .notifications),
                       "Pick a city so alerts know where to look.")
    }
}
