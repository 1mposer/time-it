import XCTest
@testable import TimeIt

/// ActivityStore: EMPTY on first launch (templates removed 2026-09-01),
/// persisted to UserDefaults on every mutation, and the one-time launch purge
/// that drops dormant showcase residue from pre-removal installs.
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

    private func makeStore(seeds: [AuthoredActivity] = []) -> ActivityStore {
        ActivityStore(defaults: defaults, seeds: seeds)
    }

    private func makeActivity(id: String = UUID().uuidString,
                              label: String = "Padel",
                              templateOrigin: String? = nil,
                              window: WindowSpec? = WindowSpec(startHour: 16, endHour: 19)) -> AuthoredActivity {
        AuthoredActivity(id: id,
                         label: label,
                         iconSymbol: "questionmark.circle",
                         templateOrigin: templateOrigin,
                         displayMetrics: ["temp"],
                         thresholds: ["temp": Threshold(min: 15, max: 35, required: true)],
                         window: window)
    }

    /// Persists a list directly, bypassing the store — the shape of a
    /// pre-existing install's UserDefaults.
    private func persistDirectly(_ activities: [AuthoredActivity]) {
        defaults.set(try! JSONEncoder().encode(activities), forKey: ActivityStore.storageKey)
    }

    // MARK: first launch

    func testFirstLaunchIsEmptyAndPersists() {
        let store = makeStore()

        XCTAssertTrue(store.activities.isEmpty, "no templates — first launch is the Add-CTA state")
        XCTAssertNotNil(defaults.data(forKey: ActivityStore.storageKey),
                        "the empty list persists immediately so it is stable across launches")
    }

    // MARK: mutations + persistence round-trip

    func testAddAppendsAndRoundTripsThroughUserDefaults() {
        let store = makeStore()
        let padel = makeActivity(label: "Padel")

        store.add(padel)

        XCTAssertEqual(store.activities.last?.label, "Padel")
        let fresh = makeStore()
        XCTAssertEqual(fresh.activities.map(\.id), store.activities.map(\.id))
        XCTAssertEqual(fresh.activities.last?.label, "Padel")
    }

    func testUpdateReplacesByIdWithoutChangingOrderOrId() {
        let store = makeStore()
        let first = makeActivity(label: "Padel")
        let second = makeActivity(label: "Tennis")
        store.add(first)
        store.add(second)
        var edited = first
        edited.label = "Beach Padel"

        store.update(edited)

        XCTAssertEqual(store.activities.map(\.id), [first.id, second.id], "order and id unchanged")
        XCTAssertEqual(store.activities[0].label, "Beach Padel")
        XCTAssertEqual(makeStore().activities[0].label, "Beach Padel")
    }

    func testDeleteRemovesByIdAndLastDeleteLandsTrueEmpty() {
        let store = makeStore()
        let padel = makeActivity(label: "Padel")
        store.add(padel)

        store.delete(id: padel.id)

        XCTAssertTrue(store.activities.isEmpty,
                      "deleting the last Activity lands the Add-CTA state — nothing re-seeds")
        XCTAssertTrue(makeStore().activities.isEmpty,
                      "a persisted empty list is a user choice, not a first launch — never re-seeded")
    }

    func testNoOpDeleteDoesNotPersist() {
        let store = makeStore(seeds: [makeActivity(label: "Padel")])

        store.delete(id: "ghost")

        XCTAssertEqual(store.activities.count, 1, "nothing was removed")
    }

    // MARK: launch purge — template-removal cleanup of existing installs

    func testLaunchPurgeDropsDormantLegacySeedsIncludingRetiredIds() {
        let dormantSeeds = ["cycling", "fishing-lite", "running", "stargazing"].map {
            makeActivity(id: $0, label: $0, window: nil)
        }
        let survivor = makeActivity(label: "Padel")
        persistDirectly(dormantSeeds + [survivor])

        let store = makeStore()

        XCTAssertEqual(store.activities.map(\.id), [survivor.id],
                       "dormant showcase residue is purged — incl. stargazing, retired before the catalog itself")
        XCTAssertEqual(makeStore().activities.map(\.id), [survivor.id], "the purge persists")
    }

    func testLaunchPurgeKeepsConfirmedActivitiesWhateverTheirOrigin() {
        let confirmedSeed = makeActivity(id: "cycling", label: "Cycling",
                                         window: WindowSpec(startHour: 6, endHour: 10))
        let confirmedCopy = makeActivity(label: "Morning Ride", templateOrigin: "cycling",
                                         window: WindowSpec(startHour: 6, endHour: 10))
        persistDirectly([confirmedSeed, confirmedCopy])

        let store = makeStore()

        XCTAssertEqual(store.activities.map(\.id), [confirmedSeed.id, confirmedCopy.id],
                       "a confirmed (windowed) activity is the user's, whatever its origin")
    }

    func testLaunchPurgeDropsDormantTemplateCopiesButKeepsDormantScratchWork() {
        let dormantCopy = makeActivity(label: "Ride", templateOrigin: "cycling", window: nil)
        let dormantScratch = makeActivity(label: "Padel", window: nil)
        persistDirectly([dormantCopy, dormantScratch])

        let store = makeStore()

        XCTAssertEqual(store.activities.map(\.id), [dormantScratch.id],
                       "seed-descended dormancy is residue; scratch dormancy is the user's own work")
    }

    // MARK: robustness

    func testCorruptPersistedDataFallsBackToEmpty() {
        defaults.set(Data("not json".utf8), forKey: ActivityStore.storageKey)

        let store = makeStore()

        XCTAssertTrue(store.activities.isEmpty, "corrupt data must fall back to empty, not crash")
        XCTAssertTrue(makeStore().activities.isEmpty)
    }

    // MARK: soft quantity cap

    func testAddIsRefusedAtTheSoftCap() {
        let store = makeStore()
        while store.activities.count < ActivityStore.softCap {
            XCTAssertTrue(store.add(makeActivity()), "adds under the cap must report success")
        }

        XCTAssertTrue(store.isAtCap)
        XCTAssertFalse(store.add(makeActivity(label: "One Too Many")),
                       "a refused add must report failure so the UI can react — the Add sheet is open when the cap races in via another scene")
        XCTAssertEqual(store.activities.count, ActivityStore.softCap, "the soft cap is enforced")
        XCTAssertLessThan(ActivityStore.softCap, 50, "soft cap must stay under the ADR-0005 hard ceiling")
    }
}
