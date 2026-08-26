import XCTest
@testable import TimeIt

/// Pins `TimezoneMismatch.warning` — the one-time alert body shown when the
/// chosen home's wall clock differs from the device's (the dashboard clock
/// follows the home's zone, so the user is told before it surprises them).
final class TimezoneMismatchTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_750_000_000)

    private func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier)!
    }

    func testHomeAheadOfDeviceNamesTheOffset() {
        let message = TimezoneMismatch.warning(homeName: "Bangkok",
                                               forecastZone: zone("Asia/Bangkok"),
                                               deviceZone: zone("Asia/Dubai"),
                                               at: date)
        XCTAssertEqual(message,
                       "Bangkok is 3 hours ahead of your device. Dashboard times, including the clock, follow Bangkok time.")
    }

    func testSharedWallClockNeedsNoWarning() {
        let message = TimezoneMismatch.warning(homeName: "Muscat",
                                               forecastZone: zone("Asia/Muscat"),
                                               deviceZone: zone("Asia/Dubai"),
                                               at: date)
        XCTAssertNil(message, "same GMT offset → the clock reads identically; nothing to warn about")
    }

    func testHalfHourZoneSpellsOutMinutesAndSingularHour() {
        let message = TimezoneMismatch.warning(homeName: "Mumbai",
                                               forecastZone: zone("Asia/Kolkata"),
                                               deviceZone: zone("Asia/Dubai"),
                                               at: date)
        XCTAssertEqual(message,
                       "Mumbai is 1 hour 30 minutes ahead of your device. Dashboard times, including the clock, follow Mumbai time.")
    }

    func testHomeBehindDeviceNamesTheDirection() {
        let message = TimezoneMismatch.warning(homeName: "Dubai",
                                               forecastZone: zone("Asia/Dubai"),
                                               deviceZone: zone("Asia/Bangkok"),
                                               at: date)
        XCTAssertEqual(message,
                       "Dubai is 3 hours behind your device. Dashboard times, including the clock, follow Dubai time.")
    }
}
