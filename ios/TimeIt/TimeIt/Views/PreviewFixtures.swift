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

    /// Live (range-confirmed) sample Activities — the full template catalog,
    /// windows intact, so the fixture forecast rates them: Cycling Perfect
    /// today, Fishing Lite Good tomorrow, Stargazing Perfect tonight.
    static let liveActivities: [AuthoredActivity] = SeedTemplates.all

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

    static func store(activities: [AuthoredActivity] = liveActivities,
                      preferences: PreferencesStore? = nil) -> ActivityStore {
        ActivityStore(defaults: ephemeralDefaults(),
                      seeds: activities,
                      preferences: preferences ?? self.preferences())
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
                                  store: store(activities: activities, preferences: preferences),
                                  preferences: preferences,
                                  deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!)
    }

    /// Registration on the UI-test doubles — the Settings toggle exercises
    /// the real opt-in flow without Keychain or APNs.
    static func registration(preferences: PreferencesStore? = nil) -> DeviceRegistration {
        let preferences = preferences ?? self.preferences()
        return DeviceRegistration(api: UITestDevicesAPI(),
                                  keychain: UITestKeychain(),
                                  store: store(preferences: preferences),
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
