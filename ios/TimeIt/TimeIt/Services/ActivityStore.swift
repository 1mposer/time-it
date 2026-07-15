import Foundation

/// The single source of truth for the user's authored Activity list (#5b §3).
/// Ordered (store order = request order = card order), seeded with the two
/// #5a Templates on first launch, persisted to UserDefaults on every mutation.
/// Local persistence only — cloud sync is a future issue (scoping #3).
@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    static let storageKey = "authoredActivities"

    /// Soft quantity cap (#5b §8) — a plain constant, no StoreKit. Raised
    /// behind an entitlement when Pro ships; must stay well under the
    /// ADR-0005 ~50 hard ceiling.
    static let softCap = 10

    @Published private(set) var activities: [AuthoredActivity] = []

    private let defaults: UserDefaults
    private let seeds: [AuthoredActivity]

    init(defaults: UserDefaults = .standard,
         seeds: [AuthoredActivity] = SeedTemplates.firstLaunchSeeds) {
        self.defaults = defaults
        self.seeds = seeds
        load()
    }

    var isAtCap: Bool { activities.count >= Self.softCap }

    // MARK: mutations — every one persists synchronously

    /// Appends and persists. Returns false (storing nothing) at the soft cap —
    /// callers must not assume success: the cap can be reached between opening
    /// the Add flow and saving (e.g. a second scene sharing this store).
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

    func delete(id: String) {
        activities.removeAll { $0.id == id }
        persist()
    }

    // MARK: persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            // First launch: seed and persist immediately so the seed is stable.
            // A persisted EMPTY list is a user choice, not a first launch —
            // it decodes fine below and must not re-seed.
            activities = seeds
            persist()
            return
        }
        do {
            activities = try JSONDecoder().decode([AuthoredActivity].self, from: data)
        } catch {
            // Corrupt/older shape: fall back to the seeds rather than crash.
            activities = seeds
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(activities) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
