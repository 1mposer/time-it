import XCTest
import CoreLocation
@testable import TimeIt

/// PreferencesStore owns the optional home location (#5b §5): persisted
/// locally, used over GPS by the dashboard, cleared back to GPS.
@MainActor
final class PreferencesStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PreferencesStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testHomeLocationDefaultsToNil() {
        XCTAssertNil(PreferencesStore(defaults: defaults).homeLocation)
    }

    func testHomeLocationPersistsAndRestores() {
        let store = PreferencesStore(defaults: defaults)
        store.homeLocation = SavedLocation(name: "Abu Dhabi", lat: 24.4539, lon: 54.3773)

        let fresh = PreferencesStore(defaults: defaults)

        XCTAssertEqual(fresh.homeLocation, SavedLocation(name: "Abu Dhabi", lat: 24.4539, lon: 54.3773))
    }

    func testClearingReturnsToNilAndPersists() {
        let store = PreferencesStore(defaults: defaults)
        store.homeLocation = SavedLocation(name: "Abu Dhabi", lat: 24.4539, lon: 54.3773)

        store.homeLocation = nil

        XCTAssertNil(PreferencesStore(defaults: defaults).homeLocation, "clearing must persist (back to GPS)")
    }

    func testCorruptHomeLocationDataFallsBackToNil() {
        defaults.set(Data("garbage".utf8), forKey: PreferencesStore.homeLocationKey)

        XCTAssertNil(PreferencesStore(defaults: defaults).homeLocation)
    }
}
