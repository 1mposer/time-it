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

    // MARK: the wind-speed unit (#26)

    func testWindSpeedUnitDefaultsToKmhAndPersists() {
        XCTAssertEqual(PreferencesStore(defaults: defaults).windSpeedUnit, .kmh,
                       "km/h is the wire unit and the default")

        let store = PreferencesStore(defaults: defaults)
        store.windSpeedUnit = .knots

        XCTAssertEqual(PreferencesStore(defaults: defaults).windSpeedUnit, .knots)
    }

    func testUnknownPersistedWindSpeedUnitFallsBackToKmh() {
        defaults.set("furlongs", forKey: PreferencesStore.windSpeedUnitKey)

        XCTAssertEqual(PreferencesStore(defaults: defaults).windSpeedUnit, .kmh)
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

/// The unit is display-only (#26): a fixed factor over the km/h wire value,
/// exact both ways.
final class WindSpeedUnitTests: XCTestCase {

    func testKmhIsTheIdentity() {
        XCTAssertEqual(WindSpeedUnit.kmh.fromKmh(25), 25)
        XCTAssertEqual(WindSpeedUnit.kmh.toKmh(25), 25)
        XCTAssertEqual(WindSpeedUnit.kmh.label, "km/h")
    }

    func testKnotsUseTheExactInternationalDefinition() {
        XCTAssertEqual(WindSpeedUnit.knots.fromKmh(1.852), 1, accuracy: 1e-12, "1 kn = 1.852 km/h")
        XCTAssertEqual(WindSpeedUnit.knots.toKmh(10), 18.52, accuracy: 1e-12)
        XCTAssertEqual(WindSpeedUnit.knots.fromKmh(25), 13.499, accuracy: 0.001)
        XCTAssertEqual(WindSpeedUnit.knots.label, "kn")
    }

    func testRoundTripIsExact() {
        for kmh in [0.0, 7.0, 25.0, 80.0] {
            XCTAssertEqual(WindSpeedUnit.knots.toKmh(WindSpeedUnit.knots.fromKmh(kmh)), kmh, accuracy: 1e-9)
        }
    }

    func testRawValuesAreStableForPersistence() {
        XCTAssertEqual(WindSpeedUnit.kmh.rawValue, "kmh")
        XCTAssertEqual(WindSpeedUnit.knots.rawValue, "knots")
    }
}
