import Foundation

/// A geocoded place the user chose as home. When set, the dashboard fetches
/// for these coords instead of GPS.
struct SavedLocation: Codable, Equatable {
    var name: String
    var lat: Double
    var lon: Double
    /// Disambiguation shown in the city picker ("Ontario, Canada"). Optional
    /// so previously persisted values still decode. Participates in the
    /// synthesized Equatable like every field — the home-change refetch
    /// sink's removeDuplicates relies on this.
    var region: String? = nil
}

/// User preferences that aren't the activity list: the optional home location
/// plus the last-resolved cache. Persists locally; no cloud sync.
@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    static let homeLocationKey = "homeLocation"
    static let lastResolvedLocationKey = "lastResolvedLocation"
    static let dismissedTemplatesKey = "dismissedTemplates"
    static let showPhrasesKey = "showPhrases"
    static let pushCalloutDismissedKey = "pushCalloutDismissed"

    /// nil = follow the device location (then the last-resolved cache).
    @Published var homeLocation: SavedLocation? {
        didSet { persist(homeLocation, key: Self.homeLocationKey) }
    }

    /// The location the most recent successful rating actually used. Read
    /// only when home and GPS are both unavailable — real data the user has
    /// seen before beats an empty dashboard. Clearing home does NOT clear
    /// this.
    @Published var lastResolvedLocation: SavedLocation? {
        didSet { persist(lastResolvedLocation, key: Self.lastResolvedLocationKey) }
    }

    /// Showcase templates the user dismissed ("✕ not for me"). A dismissal
    /// survives the delete-all re-seed — only these ids stay gone.
    @Published var dismissedTemplateIds: Set<String> {
        didSet { persist(dismissedTemplateIds.isEmpty ? nil : dismissedTemplateIds, key: Self.dismissedTemplatesKey) }
    }

    /// The phrases toggle — default OFF (the card carries quality in color
    /// alone). The system's Differentiate Without Color force-enables phrases
    /// regardless of this value (`TrajectoryPhrase.phrasesEnabled`).
    @Published var showPhrases: Bool {
        didSet { defaults.set(showPhrases, forKey: Self.showPhrasesKey) }
    }

    /// The dashboard callout is one-time — ✕ hides it for good (enabling
    /// notifications hides it without setting this).
    @Published var pushCalloutDismissed: Bool {
        didSet { defaults.set(pushCalloutDismissed, forKey: Self.pushCalloutDismissedKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeLocation = Self.load(Self.homeLocationKey, from: defaults)
        lastResolvedLocation = Self.load(Self.lastResolvedLocationKey, from: defaults)
        dismissedTemplateIds = Self.load(Self.dismissedTemplatesKey, from: defaults) ?? []
        showPhrases = defaults.bool(forKey: Self.showPhrasesKey)
        pushCalloutDismissed = defaults.bool(forKey: Self.pushCalloutDismissedKey)
    }

    private static func load<Value: Decodable>(_ key: String, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func persist<Value: Encodable>(_ value: Value?, key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
