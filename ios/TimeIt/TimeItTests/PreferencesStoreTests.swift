import XCTest
import CoreLocation
@testable import TimeIt

/// PreferencesStore owns the optional home location: persisted locally, used
/// over GPS by the dashboard, cleared back to GPS.
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

    // MARK: last-resolved cache

    func testLastResolvedLocationPersistsAndRestores() {
        let store = PreferencesStore(defaults: defaults)
        store.lastResolvedLocation = SavedLocation(name: "Toronto", lat: 43.6532, lon: -79.3832)

        let fresh = PreferencesStore(defaults: defaults)

        XCTAssertEqual(fresh.lastResolvedLocation, SavedLocation(name: "Toronto", lat: 43.6532, lon: -79.3832))
    }

    func testClearingHomeDoesNotClearLastResolved() {
        let store = PreferencesStore(defaults: defaults)
        store.homeLocation = SavedLocation(name: "Abu Dhabi", lat: 24.4539, lon: 54.3773)
        store.lastResolvedLocation = SavedLocation(name: "Abu Dhabi", lat: 24.4539, lon: 54.3773)

        store.homeLocation = nil

        XCTAssertEqual(PreferencesStore(defaults: defaults).lastResolvedLocation?.name, "Abu Dhabi",
                       "the cache is the safety net for exactly this case — clearing home must not empty it")
    }

    // MARK: the phrases toggle

    func testPushCalloutDismissedDefaultsFalseAndPersists() {
        XCTAssertFalse(PreferencesStore(defaults: defaults).pushCalloutDismissed,
                       "the callout shows until the user dismisses it (push-client spec §1)")

        let store = PreferencesStore(defaults: defaults)
        store.pushCalloutDismissed = true

        XCTAssertTrue(PreferencesStore(defaults: defaults).pushCalloutDismissed,
                      "one-time: a dismissal survives relaunch")
    }

    func testShowPhrasesDefaultsOffAndPersists() {
        XCTAssertFalse(PreferencesStore(defaults: defaults).showPhrases,
                       "spec 14 §5: phrases default OFF — the card shows no words")

        let store = PreferencesStore(defaults: defaults)
        store.showPhrases = true

        XCTAssertTrue(PreferencesStore(defaults: defaults).showPhrases)
    }

    func testPreFiveCSavedLocationDecodesWithoutRegion() throws {
        // A SavedLocation persisted without the optional `region` field must
        // still decode.
        let legacy = Data(#"{"name":"Dubai Marina","lat":25.08,"lon":55.14}"#.utf8)
        defaults.set(legacy, forKey: PreferencesStore.homeLocationKey)

        let store = PreferencesStore(defaults: defaults)

        XCTAssertEqual(store.homeLocation?.name, "Dubai Marina")
        XCTAssertNil(store.homeLocation?.region)
    }
}
