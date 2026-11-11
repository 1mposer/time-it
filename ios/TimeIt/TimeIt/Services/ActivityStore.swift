import Foundation

/// The single source of truth for the user's authored Activity list.
/// Ordered (store order = request order = card order), EMPTY on first launch
/// (the dashboard's Add card is the only path in — the template showcase was
/// removed 2026-09-01), persisted to UserDefaults on every mutation.
@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore(purgesForBuild10: true)

    static let storageKey = "authoredActivities"

    /// The build-10 purge's stored marker (owner ruling 2026-11-11): set once
    /// the purge has run, on every load path, so it runs exactly once per
    /// install. A fixed key — never the bundle version, which App Store
    /// Connect may assign differently.
    static let build10PurgeKey = "activityPurge.build10"

    /// Soft quantity cap — must stay well under the server's ~50 hard
    /// ceiling (ADR-0005).
    static let softCap = 10

    /// Every id the retired seed catalog ever shipped (incl. "stargazing",
    /// dropped from the catalog before the catalog itself was removed) — the
    /// launch-purge target set. A DORMANT row with one of these ids is
    /// showcase residue on an existing install, not user data.
    static let legacySeedIds: Set<String> = ["cycling", "fishing-lite", "running", "stargazing"]

    @Published private(set) var activities: [AuthoredActivity] = []

    /// True when THIS load ran the build-10 purge over a stored list — the
    /// push registration reads it to send one empty snapshot (the server
    /// goes dormant; the device row is never deleted, ADR-0010).
    private(set) var purgedOnLoad = false

    private let defaults: UserDefaults
    /// First-load contents when nothing is persisted. Production passes
    /// nothing (empty first launch) — this is a test/preview seam only.
    private let seeds: [AuthoredActivity]

    /// `purgesForBuild10` is the production switch (the shared store only):
    /// test stores default to off so a pre-persisted list loads as written.
    init(defaults: UserDefaults = .standard,
         seeds: [AuthoredActivity] = [],
         purgesForBuild10: Bool = false) {
        self.defaults = defaults
        self.seeds = seeds
        if purgesForBuild10 { runBuild10PurgeIfNeeded() }
        load()
    }

    /// The build-10 purge (owner ruling 2026-11-11 — every install starts
    /// empty on this build): on the first launch that carries the marker
    /// check, every stored Activity and the per-card state keyed on them
    /// (the collapsed-card ids) are deleted. A fresh install has nothing to
    /// purge and is only stamped. A UI-test mock run is stamped without
    /// purging — its seeded store is the harness's starting state.
    private func runBuild10PurgeIfNeeded() {
        guard !defaults.bool(forKey: Self.build10PurgeKey) else { return }
        defaults.set(true, forKey: Self.build10PurgeKey)
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun { return }
        #endif
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        let hadActivities = (try? JSONDecoder().decode([AuthoredActivity].self, from: data))
            .map { !$0.isEmpty } ?? true
        defaults.set(try? JSONEncoder().encode([AuthoredActivity]()), forKey: Self.storageKey)
        defaults.removeObject(forKey: PreferencesStore.collapsedCardsKey)
        purgedOnLoad = hadActivities
    }

    var isAtCap: Bool { activities.count >= Self.softCap }

    // MARK: mutations — every one persists synchronously

    /// Appends and persists. Returns false (storing nothing) at the soft cap —
    /// callers must not assume success.
    @discardableResult
    func add(_ activity: AuthoredActivity) -> Bool {
        guard !isAtCap else { return false }
        activities.append(activity)
        persist()
        return true
    }

    func update(_ activity: AuthoredActivity) {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[index] = activity
        persist()
    }

    /// Deleting the last Activity lands the true-empty Add-CTA state — there
    /// is no showcase to re-seed. A no-op delete (unknown id) never persists.
    func delete(id: String) {
        let countBefore = activities.count
        activities.removeAll { $0.id == id }
        guard activities.count != countBefore else { return }
        persist()
    }

    /// True when `move(id:by:)` would land inside the list — the card
    /// menu's Move Up / Move Down enable on it.
    func canMove(id: String, by offset: Int) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        return offset != 0 && activities.indices.contains(index + offset)
    }

    /// Reorders one Activity by `offset` places (−1 = up) and persists —
    /// store order is card order and request order. Past either end, or an
    /// unknown id, is a no-op that never persists. The dashboard reloads
    /// through the forecast cache with no POST (lane CACHE's rule).
    func move(id: String, by offset: Int) {
        guard canMove(id: id, by: offset),
              let index = activities.firstIndex(where: { $0.id == id }) else { return }
        let activity = activities.remove(at: index)
        activities.insert(activity, at: index + offset)
        persist()
    }

    // MARK: persistence

    /// First launch (no stored data) and corrupt decodes land on the seam's
    /// `seeds` — empty in production. A persisted EMPTY list is a user
    /// choice, not a first launch — never re-seed it.
    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            activities = seeds
            persist()
            return
        }
        do {
            let decoded = try JSONDecoder().decode([AuthoredActivity].self, from: data)
            activities = Self.purgingLegacySeeds(decoded)
            if activities.count != decoded.count { persist() }
        } catch {
            activities = seeds
            persist()
        }
    }

    /// The 2026-09-01 template-removal cleanup: a DORMANT activity descending
    /// from the retired seed catalog (a never-confirmed showcase card) is
    /// dropped; anything the user confirmed (windowed) or authored from
    /// scratch survives, whatever its origin. Idempotent — safe on every load.
    static func purgingLegacySeeds(_ list: [AuthoredActivity]) -> [AuthoredActivity] {
        list.filter { activity in
            let seedDescended = activity.templateOrigin != nil || legacySeedIds.contains(activity.id)
            return !(activity.isDormant && seedDescended)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(activities) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
