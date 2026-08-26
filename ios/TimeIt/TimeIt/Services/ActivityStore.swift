import Foundation

/// The single source of truth for the user's authored Activity list.
/// Ordered (store order = request order = card order), seeded DORMANT on
/// first launch, persisted to UserDefaults on every mutation.
@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    static let storageKey = "authoredActivities"

    /// Soft quantity cap — must stay well under the server's ~50 hard
    /// ceiling (ADR-0005).
    static let softCap = 10

    @Published private(set) var activities: [AuthoredActivity] = []

    private let defaults: UserDefaults
    private let seeds: [AuthoredActivity]
    /// Dismissed template ids filter the delete-all re-seed.
    private let preferences: PreferencesStore

    /// The shared singleton is resolved inside the body — default arguments
    /// would evaluate in the caller's context.
    init(defaults: UserDefaults = .standard,
         seeds: [AuthoredActivity] = SeedTemplates.firstLaunchSeeds,
         preferences: PreferencesStore? = nil) {
        self.defaults = defaults
        self.seeds = seeds
        self.preferences = preferences ?? PreferencesStore.shared
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

    /// Deleting the last Activity re-seeds the showcase; a no-op delete
    /// (unknown id) must never persist or re-seed.
    func delete(id: String) {
        let countBefore = activities.count
        activities.removeAll { $0.id == id }
        guard activities.count != countBefore else { return }
        if activities.isEmpty {
            activities = reseededShowcase()
        }
        persist()
    }

    /// "✕ not for me" on a showcase card — records the dismissal BEFORE
    /// deleting, so dismissing the last card re-seeds without it. Only seed
    /// ids enter the dismissal ledger.
    func dismissTemplate(id: String) {
        if seeds.contains(where: { $0.id == id }) {
            preferences.dismissedTemplateIds.insert(id)
        }
        delete(id: id)
    }

    /// The delete-all re-seed: non-dismissed seed templates come back DORMANT
    /// so the dashboard always offers a next action.
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

    /// Seeds on true first launch (no stored data) or a corrupt decode. A
    /// persisted EMPTY list is a user choice, not a first launch — never re-seed it.
    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            activities = seeds
            persist()
            return
        }
        do {
            activities = try JSONDecoder().decode([AuthoredActivity].self, from: data)
        } catch {
            activities = seeds
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(activities) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
