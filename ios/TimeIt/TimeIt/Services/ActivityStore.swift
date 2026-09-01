import Foundation

/// The single source of truth for the user's authored Activity list.
/// Ordered (store order = request order = card order), EMPTY on first launch
/// (the dashboard's Add card is the only path in — the template showcase was
/// removed 2026-09-01), persisted to UserDefaults on every mutation.
@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    static let storageKey = "authoredActivities"

    /// Soft quantity cap — must stay well under the server's ~50 hard
    /// ceiling (ADR-0005).
    static let softCap = 10

    /// Every id the retired seed catalog ever shipped (incl. "stargazing",
    /// dropped from the catalog before the catalog itself was removed) — the
    /// launch-purge target set. A DORMANT row with one of these ids is
    /// showcase residue on an existing install, not user data.
    static let legacySeedIds: Set<String> = ["cycling", "fishing-lite", "running", "stargazing"]

    @Published private(set) var activities: [AuthoredActivity] = []

    private let defaults: UserDefaults
    /// First-load contents when nothing is persisted. Production passes
    /// nothing (empty first launch) — this is a test/preview seam only.
    private let seeds: [AuthoredActivity]

    init(defaults: UserDefaults = .standard,
         seeds: [AuthoredActivity] = []) {
        self.defaults = defaults
        self.seeds = seeds
        load()
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
