import Combine
import CoreLocation
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var forecast: ForecastResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    /// True when the last failure is worth retrying (502 / unreachable server),
    /// as opposed to a server defect (500). Drives the error view's framing.
    private(set) var isTransientError = false

    /// Fallback when no device location is available (Simulator, denied, timeout).
    static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 25.1627, longitude: 55.2077) // Dubai

    private let api: RatingFetching
    private let locationProvider: LocationProviding
    /// Exposed so views mutate and observe the SAME store the requests are
    /// built from — a separately-injected copy would silently diverge.
    let store: ActivityStore
    private let preferences: PreferencesStore
    private var cancellables: Set<AnyCancellable> = []
    /// Monotonic guard: only the newest in-flight load may publish its result,
    /// so a slow pre-mutation response can't overwrite a newer one.
    private var loadGeneration = 0
    /// The coordinate the most recent POST actually used. Lets a late GPS fix
    /// trigger a reload only when it would move the forecast location — the
    /// distance gate is what prevents a request→fix→request loop, since every
    /// load calls requestLocation() and every fix lands back in the sink below.
    private var lastFetchedCoordinate: CLLocationCoordinate2D?

    init(api: RatingFetching = APIClient.shared,
         locationProvider: LocationProviding? = nil,
         store: ActivityStore? = nil,
         preferences: PreferencesStore? = nil) {
        self.api = api
        // Resolved here, not as default arguments — the shared singletons are
        // main-actor-isolated and default arguments evaluate in the caller's context.
        self.locationProvider = locationProvider ?? LocationManager.shared
        self.store = store ?? ActivityStore.shared
        self.preferences = preferences ?? PreferencesStore.shared

        // Any store mutation (add/edit/delete) or home-location change
        // re-rates the dashboard (#5b §6). dropFirst skips the seed/initial
        // publish — the view's initial .task drives the first load.
        self.store.$activities
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { await self?.loadForecast() }
            }
            .store(in: &cancellables)
        self.preferences.$homeLocation
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { await self?.loadForecast() }
            }
            .store(in: &cancellables)
        // requestLocation() resolves AFTER the load that called it, so the
        // first fix usually arrives once a fallback forecast (Dubai, or a
        // stale cache) is already on screen. Re-rate exactly then — but only
        // while no home location overrides GPS, and only when the fix actually
        // moves the forecast somewhere new (see lastFetchedCoordinate).
        self.locationProvider.locationPublisher
            .compactMap { $0 }
            .sink { [weak self] fix in
                guard let self, self.preferences.homeLocation == nil,
                      let fetched = self.lastFetchedCoordinate,
                      Self.isMeaningfulMove(from: fetched, to: fix.coordinate) else { return }
                Task { await self.loadForecast() }
            }
            .store(in: &cancellables)
    }

    /// ~1 km at UAE latitudes — below this a fresh fix wouldn't change the
    /// hourly forecast, so refetching would only burn provider quota.
    private static func isMeaningfulMove(from a: CLLocationCoordinate2D,
                                         to b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) > 0.01 || abs(a.longitude - b.longitude) > 0.01
    }

    var timeDeriver: TimeDeriver? {
        forecast.flatMap { TimeDeriver(forecastStart: $0.forecastStart, timezone: $0.timezone) }
    }

    /// False once the user deletes their last Activity — the dashboard shows
    /// the empty state instead of POSTing an empty activities[] (ADR-0005
    /// requires non-empty).
    var hasActivities: Bool { !store.activities.isEmpty }

    func loadForecast() async {
        loadGeneration += 1
        let generation = loadGeneration

        guard hasActivities else {
            // Never POST an empty activities[] — show the empty state.
            forecast = nil
            errorMessage = nil
            isTransientError = false
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        isTransientError = false

        // Warm the GPS fix on every load (even while a home location covers
        // this fetch). The request resolves asynchronously — this load
        // proceeds with whatever is already cached (or the fallback); the
        // locationPublisher sink re-rates once a fresh fix lands somewhere new.
        locationProvider.requestLocation()

        let coordinate = resolveCoordinate()
        lastFetchedCoordinate = coordinate
        let activities = store.activities.map(\.activityInput)
        do {
            let result = try await api.fetchRatings(lat: coordinate.latitude,
                                                    lon: coordinate.longitude,
                                                    activities: activities)
            guard generation == loadGeneration else { return }
            forecast = result
        } catch let error as APIError {
            guard generation == loadGeneration else { return }
            errorMessage = error.userMessage
            isTransientError = error.isTransient
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = "Unable to reach the server. Check that it's running and try again."
            isTransientError = true
        }
        isLoading = false
    }

    /// Coordinate resolution (#5b §6): home location → device GPS → Dubai.
    private func resolveCoordinate() -> CLLocationCoordinate2D {
        if let home = preferences.homeLocation {
            return CLLocationCoordinate2D(latitude: home.lat, longitude: home.lon)
        }
        return locationProvider.location?.coordinate ?? Self.fallbackCoordinate
    }

    // MARK: authored-activity lookups (icon + nocturnal labels)

    /// The authored source of a response activity, matched by the echoed id.
    func authoredActivity(forActivityId activityId: String) -> AuthoredActivity? {
        store.activities.first { $0.id == activityId }
    }

    /// Explicit icon from the authored model; nil lets the view fall back to
    /// the legacy label heuristic (#5b §2).
    func iconSymbol(forActivityId activityId: String) -> String? {
        authoredActivity(forActivityId: activityId)?.iconSymbol
    }

    /// Nocturnality comes from the authored wrapped window — the client knows
    /// it authored the window it sent (ADR-0004 amendment); it drives the
    /// "Tonight"/"… night" day labels.
    func isNocturnal(activityId: String) -> Bool {
        authoredActivity(forActivityId: activityId)?.isNocturnal ?? false
    }

    /// The card's day: day 0 (today/tonight) ONLY — the card answers "is my
    /// range good today?". Nil when today has no window; the card renders its
    /// none-state and the week stays in the detail timeline. The roll-forward
    /// to a later day was cancelled (ADR-0004 amendment 2026-07-20).
    func cardDay(for activity: ActivityRating) -> Day? {
        activity.days.first.flatMap { $0.rating != nil ? $0 : nil }
    }

    /// The hour at the day's window start — chips read their values here.
    /// `startIndex` is a global index into hours[]; no per-day offset math.
    func windowStartHour(for day: Day) -> HourlyWeather? {
        guard let startIndex = day.startIndex,
              let hours = forecast?.hours,
              hours.indices.contains(startIndex) else {
            return nil
        }
        return hours[startIndex]
    }

    /// The half-open slice `hours[startIndex..<endIndex]` for a day's Window;
    /// empty when indices are absent or out of range.
    func windowHours(for day: Day) -> [HourlyWeather] {
        guard let startIndex = day.startIndex,
              let endIndex = day.endIndex,
              let hours = forecast?.hours,
              startIndex >= 0, startIndex < endIndex, endIndex <= hours.count else {
            return []
        }
        return Array(hours[startIndex..<endIndex])
    }
}
