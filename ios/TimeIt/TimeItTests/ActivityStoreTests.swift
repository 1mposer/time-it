import XCTest
@testable import TimeIt

/// ActivityStore is the single source of truth for the user's authored Activity
/// list (#5b §3): seeded on first launch, persisted to UserDefaults on every
/// mutation, corrupt data falls back to the seeds rather than crashing.
@MainActor
final class ActivityStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var preferences: PreferencesStore!

    override func setUp() {
        super.setUp()
        suiteName = "ActivityStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        preferences = PreferencesStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Always injects this suite's PreferencesStore — the store reads
    /// dismissed template ids at delete time (spec 14 §6 re-seed), and the
    /// shared singleton would leak state across tests.
    private func makeStore(seeds: [AuthoredActivity] = SeedTemplates.firstLaunchSeeds) -> ActivityStore {
        ActivityStore(defaults: defaults, seeds: seeds, preferences: preferences)
    }

    /// The showcase is the FULL template catalog — four cards, per the Figma
    /// Empty — Showcase frame (owner ruling 2026-08-13; Figma is authoritative).
    private let seedIds = ["cycling", "fishing-lite", "running", "stargazing"]

    private func makeActivity(id: String = UUID().uuidString, label: String = "Padel") -> AuthoredActivity {
        AuthoredActivity(id: id,
                         label: label,
                         iconSymbol: "questionmark.circle",
                         templateOrigin: nil,
                         displayMetrics: ["temp"],
                         thresholds: ["temp": Threshold(min: 15, max: 35, required: true)],
                         window: WindowSpec(startHour: 16, endHour: 19))
    }

    // MARK: seeding

    func testFirstLaunchSeedsTheFullCatalogInOrderAndPersists() {
        let store = makeStore()

        XCTAssertEqual(store.activities.map(\.id), seedIds)
        XCTAssertNotNil(defaults.data(forKey: ActivityStore.storageKey),
                        "the seed must persist immediately so it is stable across launches")
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
        var edited = store.activities[0]
        edited.label = "Road Cycling"

        store.update(edited)

        XCTAssertEqual(store.activities.map(\.id), seedIds, "order and id unchanged")
        XCTAssertEqual(store.activities[0].label, "Road Cycling")
        XCTAssertEqual(makeStore().activities[0].label, "Road Cycling")
    }

    func testDeleteRemovesById() {
        let store = makeStore()

        store.delete(id: "cycling")

        XCTAssertEqual(store.activities.map(\.id), ["fishing-lite", "running", "stargazing"])
        XCTAssertEqual(makeStore().activities.map(\.id), ["fishing-lite", "running", "stargazing"])
    }

    // MARK: spec 14 §6 — delete-all re-seeds the showcase; dismissals survive

    func testDeletingTheLastActivityReseedsTheShowcaseDormant() {
        let store = makeStore()
        store.delete(id: "cycling")
        store.delete(id: "fishing-lite")
        store.delete(id: "running")
        store.delete(id: "stargazing") // empties the list → re-seed

        XCTAssertEqual(store.activities.map(\.id), seedIds,
                       "delete-all re-seeds the showcase — the dashboard always offers a next action, never a dead end")
        XCTAssertTrue(store.activities.allSatisfy(\.isDormant),
                      "re-seeded cards land dormant, never active")
        XCTAssertEqual(makeStore().activities.map(\.id), seedIds, "the re-seed persists")
    }

    func testReseedForcesDormancyEvenFromLiveSeeds() {
        // The ruling says re-seeded cards are showcase (dormant) cards — the
        // store enforces it structurally rather than trusting the seed data.
        let liveSeed = makeActivity(id: "padel", label: "Padel") // windowed
        let store = makeStore(seeds: [liveSeed])

        store.delete(id: "padel")

        XCTAssertEqual(store.activities.map(\.id), ["padel"])
        XCTAssertTrue(store.activities.allSatisfy(\.isDormant))
    }

    func testDismissalSurvivesTheReseed() {
        let store = makeStore()

        store.dismissTemplate(id: "cycling")

        XCTAssertEqual(store.activities.map(\.id), ["fishing-lite", "running", "stargazing"],
                       "✕ removes the showcase card")
        XCTAssertTrue(preferences.dismissedTemplateIds.contains("cycling"),
                      "the dismissal is remembered in preferences")

        store.delete(id: "fishing-lite")
        store.delete(id: "running")
        store.delete(id: "stargazing") // delete-all → re-seed

        XCTAssertEqual(store.activities.map(\.id), ["fishing-lite", "running", "stargazing"],
                       "a dismissed template stays gone; a merely-deleted one returns (deletion ≠ dismissal)")
    }

    func testAllDismissedDeleteAllLandsTrueEmptyAndStaysEmptyAcrossRelaunch() {
        let store = makeStore()

        store.dismissTemplate(id: "cycling")
        store.dismissTemplate(id: "fishing-lite")
        store.dismissTemplate(id: "running")
        store.dismissTemplate(id: "stargazing") // last card → re-seed set is empty

        XCTAssertTrue(store.activities.isEmpty,
                      "every template dismissed → the true-empty Add-CTA state, not a resurrected showcase")
        XCTAssertTrue(makeStore().activities.isEmpty,
                      "a relaunch must not re-seed — a persisted empty list is a user choice, not a first launch")
    }

    func testDeleteOnATrueEmptyStoreDoesNotReseed() {
        let store = makeStore()
        store.dismissTemplate(id: "cycling")
        store.dismissTemplate(id: "fishing-lite")
        store.dismissTemplate(id: "running")
        store.dismissTemplate(id: "stargazing")

        store.delete(id: "ghost")

        XCTAssertTrue(store.activities.isEmpty,
                      "nothing was removed — a stray delete must not resurrect the showcase")
    }

    // MARK: robustness

    func testCorruptPersistedDataFallsBackToSeeds() {
        defaults.set(Data("not json".utf8), forKey: ActivityStore.storageKey)

        let store = makeStore()

        XCTAssertEqual(store.activities.map(\.id), seedIds,
                       "corrupt data must fall back to the seed set, not crash")
        // And it re-persists a decodable shape.
        XCTAssertEqual(makeStore().activities.map(\.id), seedIds)
    }

    // MARK: soft quantity cap (§8 — no StoreKit, plain constant)

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
