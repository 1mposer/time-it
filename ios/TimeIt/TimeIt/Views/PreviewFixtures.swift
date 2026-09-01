#if DEBUG
import Foundation

/// Shared wiring for #Preview blocks: reuses the hermetic UI-test doubles
/// (MockRatingService, StaticLocationProvider, UITest* fakes) so canvas
/// previews never touch the network, the Keychain, or the app's real
/// UserDefaults. DEBUG-only; never ships.
@MainActor
enum PreviewFixtures {

    /// Throwaway defaults, fresh per call — a preview's store mutations must
    /// never leak into the app's persisted state (or another preview's).
    static func ephemeralDefaults() -> UserDefaults {
        let suite = "previews.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    static let dubai = SavedLocation(name: "Dubai", lat: 25.1627, lon: 55.2077,
                                     region: "United Arab Emirates")

    /// Fully-authored sample Activities (the former seed-template values,
    /// kept as harness data after the template flow was removed) — previews
    /// and the UITEST_SEED_LIVE launch argument share them.
    static let cycling = AuthoredActivity(
        id: "cycling",
        label: "Cycling",
        iconSymbol: "figure.outdoor.cycle",
        templateOrigin: nil,
        displayMetrics: ["temp", "windSpeed", "rainFall", "uV"],
        thresholds: [
            "temp": Threshold(min: 15, max: 32, required: true),
            "windSpeed": Threshold(max: 25, required: false),
            "rainFall": Threshold(max: 0.2, required: true),
            "uV": Threshold(max: 8, required: false),
        ],
        window: WindowSpec(startHour: 6, endHour: 10)
    )

    static let fishingLite = AuthoredActivity(
        id: "fishing-lite",
        label: "Fishing Lite",
        iconSymbol: "figure.fishing",
        templateOrigin: nil,
        displayMetrics: ["temp", "windSpeed", "cloudCover"],
        thresholds: [
            "temp": Threshold(min: 12, max: 36, required: true),
            "windSpeed": Threshold(max: 25, required: true),
            "cloudCover": Threshold(max: 80, required: false),
        ],
        window: WindowSpec(startHour: 15, endHour: 19)
    )

    static let running = AuthoredActivity(
        id: "running",
        label: "Running",
        iconSymbol: "figure.run",
        templateOrigin: nil,
        displayMetrics: ["temp", "humidity", "uV", "windSpeed"],
        thresholds: [
            "temp": Threshold(min: 10, max: 33, required: true),
            "humidity": Threshold(max: 70, required: false),
            "uV": Threshold(max: 7, required: false),
        ],
        window: WindowSpec(startHour: 6, endHour: 9)
    )

    /// Live (range-confirmed) sample Activities, windows intact, so the
    /// fixture forecast rates them.
    static let liveActivities: [AuthoredActivity] = [cycling, fishingLite, running]

    /// The canned forecast the UI tests pin (56 hours from 4am Asia/Dubai).
    static var forecast: ForecastResponse {
        .uiTestFixture(for: liveActivities.map(\.activityInput))
    }

    static var timeDeriver: TimeDeriver? {
        TimeDeriver(forecastStart: forecast.forecastStart, timezone: forecast.timezone)
    }

    static func preferences(home: SavedLocation? = dubai) -> PreferencesStore {
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.homeLocation = home
        return preferences
    }

    static func store(activities: [AuthoredActivity] = liveActivities) -> ActivityStore {
        ActivityStore(defaults: ephemeralDefaults(), seeds: activities)
    }

    /// A dashboard view model on the canned forecast and a fixed Dubai home —
    /// loads instantly, no network. `.failure` renders the error state;
    /// `home: nil` (with the fixless location provider) the no-location state.
    static func dashboardViewModel(mode: MockRatingService.Mode = .success,
                                   activities: [AuthoredActivity] = liveActivities,
                                   home: SavedLocation? = dubai) -> DashboardViewModel {
        let preferences = preferences(home: home)
        return DashboardViewModel(api: MockRatingService(mode: mode),
                                  locationProvider: StaticLocationProvider(),
                                  store: store(activities: activities),
                                  preferences: preferences,
                                  deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!)
    }

    /// Registration on the UI-test doubles — the Settings toggle exercises
    /// the real opt-in flow without Keychain or APNs.
    static func registration(preferences: PreferencesStore? = nil) -> DeviceRegistration {
        let preferences = preferences ?? self.preferences()
        return DeviceRegistration(api: UITestDevicesAPI(),
                                  keychain: UITestKeychain(),
                                  store: store(),
                                  preferences: preferences,
                                  locationProvider: StaticLocationProvider(),
                                  authorizer: UITestPushAuthorizer(grants: true),
                                  registerForRemoteNotifications: {},
                                  defaults: ephemeralDefaults())
    }

    /// Canned city search so the picker's as-you-type flow works in canvas.
    struct CannedGeocoder: GeocodingProviding {
        func geocode(_ query: String) async throws -> [SavedLocation] {
            [PreviewFixtures.dubai,
             SavedLocation(name: "Bangkok", lat: 13.7563, lon: 100.5018, region: "Thailand"),
             SavedLocation(name: "Toronto", lat: 43.6532, lon: -79.3832, region: "Ontario, Canada")]
        }
    }
}
#endif
