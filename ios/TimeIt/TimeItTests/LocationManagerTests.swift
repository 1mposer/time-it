import CoreLocation
import XCTest
@testable import TimeIt

/// Which `didFailWithError` errors the manager publishes as a failed fix.
final class LocationManagerTests: XCTestCase {

    func testADenialIsNotPublishedAsAFailedFix() {
        XCTAssertFalse(LocationManager.isReportableFailure(CLError(.denied)),
                       "the authorization status carries a denial — it is never retried")
    }

    func testAMissingFixIsPublished() {
        XCTAssertTrue(LocationManager.isReportableFailure(CLError(.locationUnknown)))
        XCTAssertTrue(LocationManager.isReportableFailure(CLError(.network)))
    }

    func testANonLocationErrorIsPublished() {
        XCTAssertTrue(LocationManager.isReportableFailure(URLError(.timedOut)))
    }

    /// The real manager's `$location` emits in `willSet` — before the
    /// property holds the fix — unlike the test fakes. The empty screen's
    /// header must still take the first fix it is handed (#19).
    @MainActor
    func testARealManagersFirstFixNamesTheEmptyScreenHeader() async {
        let suiteName = "LocationManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = LocationManager()
        let vm = DashboardViewModel(api: FakeRatingService(result: .success(Fixtures.makeForecast(activities: []))),
                                    locationProvider: manager,
                                    store: ActivityStore(defaults: defaults, seeds: []),
                                    preferences: PreferencesStore(defaults: defaults),
                                    deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!)
        XCTAssertNil(vm.activeLocationName)

        manager.locationManager(CLLocationManager(),
                                didUpdateLocations: [CLLocation(latitude: 25.2048, longitude: 55.2708)])
        let deadline = Date().addingTimeInterval(2)
        while vm.activeLocationName == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(vm.activeLocationName, "Current location")
        XCTAssertFalse(vm.hasNoLocation)
    }
}
