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
    /// Read at delete time: dismissed template ids filter the spec 14 §6
    /// delete-all re-seed (a dismissal survives, a mere deletion does not).
    private let preferences: PreferencesStore

    init(defaults: UserDefaults = .standard,
         seeds: [AuthoredActivity] = SeedTemplates.firstLaunchSeeds,
         preferences: PreferencesStore? = nil) {
        self.defaults = defaults
        self.seeds = seeds
        // Resolved here, not as a default argument — the shared singleton is
        // main-actor-isolated and default arguments evaluate in the caller's
        // context (same rule as DashboardViewModel's dependencies).
        self.preferences = preferences ?? PreferencesStore.shared
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
        let countBefore = activities.count
        activities.removeAll { $0.id == id }
        // No removal → no persist and, critically, no re-seed: a stray delete
        // on the true-empty state must not resurrect the showcase.
        guard activities.count != countBefore else { return }
        if activities.isEmpty {
            activities = reseededShowcase()
        }
        persist()
    }

    /// Spec 14 §6: "✕ not for me" on a showcase card — records the dismissal
    /// (so it survives every future re-seed) BEFORE deleting, so dismissing
    /// the last card re-seeds without it.
    func dismissTemplate(id: String) {
        preferences.dismissedTemplateIds.insert(id)
        delete(id: id)
    }

    /// The delete-all re-seed (owner ruling 2026-08-12): the non-dismissed
    /// seed templates come back DORMANT — forced structurally, not trusted to
    /// the seed data — so the dashboard always offers a next action (showcase
    /// cards, or the true-empty Add CTA when every template is dismissed).
    private func reseededShowcase() -> [AuthoredActivity] {
        seeds
            .filter { !preferences.dismissedTemplateIds.contains($0.id) }
            .map { seed in
                var dormant = seed
                dormant.window = nil
                return dormant
            }
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
