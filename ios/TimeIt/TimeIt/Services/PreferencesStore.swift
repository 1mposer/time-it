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

/// The wind-speed display unit (#26). The wire, every stored threshold and
/// the slider's km/h table never change — conversion happens only where a
/// value is rendered or typed (`HourlyWeather.formatted`, `HeaderView`,
/// `ThresholdSlider`).
enum WindSpeedUnit: String, CaseIterable, Identifiable {
    case kmh
    case knots

    var id: String { rawValue }

    /// Chip / label suffix in the app's unit dialect ("13 km/h", "7 kn").
    var label: String {
        switch self {
        case .kmh: return "km/h"
        case .knots: return "kn"
        }
    }

    /// Settings row copy.
    var displayName: String {
        switch self {
        case .kmh: return "km/h"
        case .knots: return "Knots"
        }
    }

    /// Multiply a km/h value by this to get the display value (1 kn = 1.852 km/h exactly).
    var factorFromKmh: Double {
        switch self {
        case .kmh: return 1
        case .knots: return 1 / 1.852
        }
    }

    func fromKmh(_ kmh: Double) -> Double { kmh * factorFromKmh }
    func toKmh(_ value: Double) -> Double { value / factorFromKmh }
}

/// User preferences that aren't the activity list: the optional home location
/// plus the last-resolved cache. Persists locally; no cloud sync.
@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    static let homeLocationKey = "homeLocation"
    static let windSpeedUnitKey = "windSpeedUnit"
    static let lastResolvedLocationKey = "lastResolvedLocation"
    static let pushCalloutDismissedKey = "pushCalloutDismissed"
    static let timezoneWarnedHomeKey = "timezoneWarnedHome"
    static let collapsedCardsKey = "collapsedCards"

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

    /// The dashboard callout is one-time — ✕ hides it for good (enabling
    /// notifications hides it without setting this).
    @Published var pushCalloutDismissed: Bool {
        didSet { defaults.set(pushCalloutDismissed, forKey: Self.pushCalloutDismissedKey) }
    }

    /// The home whose different-clock alert was acknowledged — warned once
    /// per chosen home, not per fetch or per launch.
    @Published var timezoneWarnedHome: SavedLocation? {
        didSet { persist(timezoneWarnedHome, key: Self.timezoneWarnedHomeKey) }
    }

    /// Wind-speed display unit (#26) — default km/h, the wire unit.
    @Published var windSpeedUnit: WindSpeedUnit {
        didSet { defaults.set(windSpeedUnit.rawValue, forKey: Self.windSpeedUnitKey) }
    }

    /// Dashboard cards whose week-dot row the chevron hid (spec 05, owner
    /// ruling 2026-10-02 — remembered per card across launches). Empty =
    /// every card expanded, the natural state.
    @Published var collapsedCardIds: Set<String> {
        didSet { persist(collapsedCardIds, key: Self.collapsedCardsKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeLocation = Self.load(Self.homeLocationKey, from: defaults)
        lastResolvedLocation = Self.load(Self.lastResolvedLocationKey, from: defaults)
        pushCalloutDismissed = defaults.bool(forKey: Self.pushCalloutDismissedKey)
        timezoneWarnedHome = Self.load(Self.timezoneWarnedHomeKey, from: defaults)
        windSpeedUnit = defaults.string(forKey: Self.windSpeedUnitKey)
            .flatMap(WindSpeedUnit.init(rawValue:)) ?? .kmh
        collapsedCardIds = Self.load(Self.collapsedCardsKey, from: defaults) ?? []
    }

    /// The card chevron: hide ↔ show this card's week-dot row.
    func toggleCardCollapsed(_ id: String) {
        if collapsedCardIds.contains(id) {
            collapsedCardIds.remove(id)
        } else {
            collapsedCardIds.insert(id)
        }
    }

    /// Forgets the chevron state of deleted Activities — called with the
    /// store's live ids whenever the activity list changes.
    func pruneCollapsedCards(keeping ids: Set<String>) {
        let kept = collapsedCardIds.intersection(ids)
        if kept != collapsedCardIds { collapsedCardIds = kept }
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
