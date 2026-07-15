import Foundation

/// A geocoded place the user chose as home (#5b §5). When set, the dashboard
/// fetches for these coords instead of GPS.
struct SavedLocation: Codable, Equatable {
    var name: String
    var lat: Double
    var lon: Double
}

/// User preferences that aren't the activity list (#5b §5): currently just the
/// optional home location. Persists locally; no cloud sync (scoping #3).
@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    static let homeLocationKey = "homeLocation"

    /// nil = use GPS (then the Dubai fallback).
    @Published var homeLocation: SavedLocation? {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.homeLocationKey),
           let saved = try? JSONDecoder().decode(SavedLocation.self, from: data) {
            homeLocation = saved
        }
    }

    private func persist() {
        if let homeLocation, let data = try? JSONEncoder().encode(homeLocation) {
            defaults.set(data, forKey: Self.homeLocationKey)
        } else {
            defaults.removeObject(forKey: Self.homeLocationKey)
        }
    }
}
