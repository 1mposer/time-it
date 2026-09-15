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
    static let showPhrasesKey = "showPhrases"
    static let pushCalloutDismissedKey = "pushCalloutDismissed"
    static let timezoneWarnedHomeKey = "timezoneWarnedHome"

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

    /// The home whose different-clock alert was acknowledged — warned once
    /// per chosen home, not per fetch or per launch.
    @Published var timezoneWarnedHome: SavedLocation? {
        didSet { persist(timezoneWarnedHome, key: Self.timezoneWarnedHomeKey) }
    }

    /// Wind-speed display unit (#26) — default km/h, the wire unit.
    @Published var windSpeedUnit: WindSpeedUnit {
        didSet { defaults.set(windSpeedUnit.rawValue, forKey: Self.windSpeedUnitKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homeLocation = Self.load(Self.homeLocationKey, from: defaults)
        lastResolvedLocation = Self.load(Self.lastResolvedLocationKey, from: defaults)
        showPhrases = defaults.bool(forKey: Self.showPhrasesKey)
        pushCalloutDismissed = defaults.bool(forKey: Self.pushCalloutDismissedKey)
        timezoneWarnedHome = Self.load(Self.timezoneWarnedHomeKey, from: defaults)
        windSpeedUnit = defaults.string(forKey: Self.windSpeedUnitKey)
            .flatMap(WindSpeedUnit.init(rawValue:)) ?? .kmh
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
