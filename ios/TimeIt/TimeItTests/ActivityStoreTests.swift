import XCTest
@testable import TimeIt

/// ActivityStore is the single source of truth for the user's authored Activity
/// list (#5b §3): seeded on first launch, persisted to UserDefaults on every
/// mutation, corrupt data falls back to the seeds rather than crashing.
@MainActor
final class ActivityStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ActivityStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeActivity(id: String = UUID().uuidString, label: String = "Padel") -> AuthoredActivity {
        AuthoredActivity(id: id,
                         label: label,
                         iconSymbol: "questionmark.circle",
                         templateOrigin: nil,
                         displayMetrics: ["temp"],
                         thresholds: ["temp": Threshold(min: 15, max: 35, required: true)],
                         window: nil)
    }

    // MARK: seeding

    func testFirstLaunchSeedsTheTwoTemplatesInOrderAndPersists() {
        let store = ActivityStore(defaults: defaults)

        XCTAssertEqual(store.activities.map(\.id), ["cycling", "fishing-lite"])
        XCTAssertNotNil(defaults.data(forKey: ActivityStore.storageKey),
                        "the seed must persist immediately so it is stable across launches")
    }

    func testDoesNotReseedWhenPersistedListIsEmpty() {
        let store = ActivityStore(defaults: defaults)
        store.delete(id: "cycling")
        store.delete(id: "fishing-lite")

        let fresh = ActivityStore(defaults: defaults)

        XCTAssertTrue(fresh.activities.isEmpty, "an intentionally-emptied list must not re-seed")
    }

    // MARK: mutations + persistence round-trip

    func testAddAppendsAndRoundTripsThroughUserDefaults() {
        let store = ActivityStore(defaults: defaults)
        let padel = makeActivity(label: "Padel")

        store.add(padel)

        XCTAssertEqual(store.activities.last?.label, "Padel")
        let fresh = ActivityStore(defaults: defaults)
        XCTAssertEqual(fresh.activities.map(\.id), store.activities.map(\.id))
        XCTAssertEqual(fresh.activities.last?.label, "Padel")
    }

    func testUpdateReplacesByIdWithoutChangingOrderOrId() {
        let store = ActivityStore(defaults: defaults)
        var edited = store.activities[0]
        edited.label = "Road Cycling"

        store.update(edited)

        XCTAssertEqual(store.activities.map(\.id), ["cycling", "fishing-lite"], "order and id unchanged")
        XCTAssertEqual(store.activities[0].label, "Road Cycling")
        XCTAssertEqual(ActivityStore(defaults: defaults).activities[0].label, "Road Cycling")
    }

    func testDeleteRemovesById() {
        let store = ActivityStore(defaults: defaults)

        store.delete(id: "cycling")

        XCTAssertEqual(store.activities.map(\.id), ["fishing-lite"])
        XCTAssertEqual(ActivityStore(defaults: defaults).activities.map(\.id), ["fishing-lite"])
    }

    func testMoveReordersAndPersists() {
        let store = ActivityStore(defaults: defaults)

        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(store.activities.map(\.id), ["fishing-lite", "cycling"])
        XCTAssertEqual(ActivityStore(defaults: defaults).activities.map(\.id), ["fishing-lite", "cycling"])
    }

    // MARK: robustness

    func testCorruptPersistedDataFallsBackToSeeds() {
        defaults.set(Data("not json".utf8), forKey: ActivityStore.storageKey)

        let store = ActivityStore(defaults: defaults)

        XCTAssertEqual(store.activities.map(\.id), ["cycling", "fishing-lite"],
                       "corrupt data must fall back to the seed set, not crash")
        // And it re-persists a decodable shape.
        XCTAssertEqual(ActivityStore(defaults: defaults).activities.map(\.id), ["cycling", "fishing-lite"])
    }

    // MARK: soft quantity cap (§8 — no StoreKit, plain constant)

    func testAddIsRefusedAtTheSoftCap() {
        let store = ActivityStore(defaults: defaults)
        while store.activities.count < ActivityStore.softCap {
            store.add(makeActivity())
        }

        XCTAssertTrue(store.isAtCap)
        store.add(makeActivity(label: "One Too Many"))
        XCTAssertEqual(store.activities.count, ActivityStore.softCap, "the soft cap is enforced")
        XCTAssertLessThan(ActivityStore.softCap, 50, "soft cap must stay under the ADR-0005 hard ceiling")
    }
}
