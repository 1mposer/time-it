import Foundation

/// A geocoded place the user chose as home (#5b §5). When set, the dashboard
/// fetches for these coords instead of GPS.
struct SavedLocation: Codable, Equatable {
    var name: String
    var lat: Double
    var lon: Double
    /// Disambiguation shown in the city picker ("Ontario, Canada"). Optional
    /// so pre-#5c persisted values still decode. Participates in the
    /// synthesized Equatable like every field — which the home-change
    /// refetch sink's removeDuplicates relies on.
    var region: String? = nil
}

/// User preferences that aren't the activity list (#5b §5): the optional home
/// location plus the last-resolved cache (#5c). Persists locally; no cloud
/// sync (scoping #3).
@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    static let homeLocationKey = "homeLocation"
    static let lastResolvedLocationKey = "lastResolvedLocation"

    /// nil = follow the device location (#5c: then the last-resolved cache).
    @Published var homeLocation: SavedLocation? {
        didSet { persist(homeLocation, key: Self.homeLocationKey) }
    }

    /// #5c: the location the most recent successful rating actually used.
    /// Read only when home and GPS are both unavailable — real data the user
    /// has seen before beats an empty dashboard. Clearing home does NOT clear
    /// this.
    @Published var lastResolvedLocation: SavedLocation? {
        didSet { persist(lastResolvedLocation, key: Self.lastResolvedLocationKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeLocation = Self.load(Self.homeLocationKey, from: defaults)
        lastResolvedLocation = Self.load(Self.lastResolvedLocationKey, from: defaults)
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> SavedLocation? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedLocation.self, from: data)
    }

    private func persist(_ location: SavedLocation?, key: String) {
        if let location, let data = try? JSONEncoder().encode(location) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
