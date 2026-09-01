import Combine
import CoreLocation
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var forecast: ForecastResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// True when no location could be resolved — the dashboard shows the
    /// no-location empty state.
    @Published private(set) var hasNoLocation = false
    /// Header label for the active location (city name, "Current location",
    /// or the cached name); nil when none resolved.
    @Published private(set) var activeLocationName: String?
    /// The one-time "home runs on a different clock" alert body; nil = no
    /// alert. Set after a successful home-location fetch whose zone's wall
    /// clock differs from the device's.
    @Published private(set) var timezoneWarning: String?

    /// True when the last failure is retryable (502 / unreachable server)
    /// rather than a server defect (500).
    private(set) var isTransientError = false

    private let api: RatingFetching
    private let locationProvider: LocationProviding
    /// The device's own zone (injected for tests) — the warning and the
    /// header clock compare against it; CoreLocation is never involved.
    private let deviceTimeZone: TimeZone
    /// Shared with views so they mutate the same store requests are built from.
    let store: ActivityStore
    /// Shared with the city-picker sheet for the same reason as `store`.
    let preferences: PreferencesStore
    private var cancellables: Set<AnyCancellable> = []
    /// Monotonic guard — only the newest in-flight load may publish its result.
    private var loadGeneration = 0
    /// Coordinate of the last POST; a new GPS fix reloads only when it moves
    /// meaningfully. nil = no POST yet, so any first fix triggers a load.
    private var lastFetchedCoordinate: CLLocationCoordinate2D?

    /// Where the location chain resolved: home → GPS → last-resolved cache.
    private enum ActiveLocation {
        case home(SavedLocation)
        case gps(CLLocationCoordinate2D)
        case cached(SavedLocation)

        var coordinate: CLLocationCoordinate2D {
            switch self {
            case .home(let saved), .cached(let saved):
                return CLLocationCoordinate2D(latitude: saved.lat, longitude: saved.lon)
            case .gps(let coordinate):
                return coordinate
            }
        }

        var displayName: String {
            switch self {
            case .home(let saved):
                return saved.name
            case .gps:
                return "Current location"
            case .cached(let saved):
                return saved.name.isEmpty ? "Last known location" : saved.name
            }
        }

        /// What a successful fetch persists; a GPS fix has no place name, so
        /// it saves an empty one.
        var savedLocation: SavedLocation {
            switch self {
            case .home(let saved), .cached(let saved):
                return saved
            case .gps(let coordinate):
                return SavedLocation(name: "", lat: coordinate.latitude, lon: coordinate.longitude)
            }
        }
    }

    /// Wires the reactive reloads (store/home changes, meaningful GPS moves,
    /// permission grants). Shared singletons are resolved inside the body —
    /// default arguments would evaluate in the caller's context.
    init(api: RatingFetching = APIClient.shared,
         locationProvider: LocationProviding? = nil,
         store: ActivityStore? = nil,
         preferences: PreferencesStore? = nil,
         deviceTimeZone: TimeZone = .current) {
        self.api = api
        self.deviceTimeZone = deviceTimeZone
        self.locationProvider = locationProvider ?? LocationManager.shared
        self.store = store ?? ActivityStore.shared
        self.preferences = preferences ?? PreferencesStore.shared

        self.store.$activities
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleReload()
            }
            .store(in: &cancellables)
        self.preferences.$homeLocation
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleReload()
            }
            .store(in: &cancellables)
        self.locationProvider.locationPublisher
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] fix in
                guard let self, self.preferences.homeLocation == nil else { return }
                if let fetched = self.lastFetchedCoordinate,
                   !Self.isMeaningfulMove(from: fetched, to: fix.coordinate) { return }
                self.scheduleReload()
            }
            .store(in: &cancellables)
        self.locationProvider.authorizationPublisher
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] status in
                guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
                self?.locationProvider.requestLocation()
            }
            .store(in: &cancellables)

        activeLocationName = resolveActiveLocation()?.displayName
    }

    /// Bumps the generation before scheduling so an in-flight load can't
    /// publish stale state in the gap.
    private func scheduleReload() {
        loadGeneration += 1
        Task { await loadForecast() }
    }

    /// ~1 km — below this a fresh fix wouldn't change the hourly forecast.
    private static func isMeaningfulMove(from a: CLLocationCoordinate2D,
                                         to b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) > 0.01 || abs(a.longitude - b.longitude) > 0.01
    }

    var timeDeriver: TimeDeriver? {
        forecast.flatMap { TimeDeriver(forecastStart: $0.forecastStart, timezone: $0.timezone) }
    }

    /// False once the last Activity is deleted — the dashboard shows the
    /// empty state instead of POSTing an empty activities[] (ADR-0005
    /// requires non-empty).
    var hasActivities: Bool { !store.activities.isEmpty }

    /// Only live (non-dormant) Activities are ever sent in a request.
    var liveActivities: [AuthoredActivity] { store.activities.filter { !$0.isDormant } }

    /// False when nothing is live — no request is made.
    var hasLiveActivities: Bool { !liveActivities.isEmpty }

    /// True when "Enable location" should deep-link to system Settings
    /// instead of firing the permission prompt.
    var locationPermissionDenied: Bool {
        locationProvider.authorizationStatus == .denied
    }

    /// Restricted users can't toggle the permission, so the view shows honest
    /// copy instead of a dead-end CTA.
    var locationPermissionRestricted: Bool {
        locationProvider.authorizationStatus == .restricted
    }

    private var isAuthorized: Bool {
        locationProvider.authorizationStatus == .authorizedWhenInUse
            || locationProvider.authorizationStatus == .authorizedAlways
    }

    /// The "Enable location" CTA: fires the system prompt when not yet asked;
    /// warms a fresh fix when already authorized.
    func requestLocationAccess() {
        if isAuthorized {
            locationProvider.requestLocation()
        } else {
            locationProvider.requestAuthorization()
        }
    }

    /// First-launch onboarding (issue #16 — reverses audit F1 for the cold
    /// start): fire the system prompt immediately, so a new user defaults to
    /// where they actually are. The grant flows through the existing sinks
    /// (authorization change → fix request → reload).
    func requestInitialLocationPermissionIfNeeded() {
        guard preferences.homeLocation == nil,
              locationProvider.authorizationStatus == .notDetermined else { return }
        locationProvider.requestAuthorization()
    }

    /// Resolves the active location and fetches ratings for the live
    /// Activities; publishes forecast/error/empty-state accordingly.
    func loadForecast() async {
        loadGeneration += 1
        let generation = loadGeneration

        guard hasLiveActivities else {
            forecast = nil
            errorMessage = nil
            isTransientError = false
            isLoading = false
            let active = resolveActiveLocation()
            hasNoLocation = active == nil
            activeLocationName = active?.displayName
            return
        }

        isLoading = true
        errorMessage = nil
        isTransientError = false

        if isAuthorized {
            locationProvider.requestLocation()
        }

        guard let active = resolveActiveLocation() else {
            forecast = nil
            hasNoLocation = true
            activeLocationName = nil
            isLoading = false
            return
        }
        hasNoLocation = false
        activeLocationName = active.displayName

        let coordinate = active.coordinate
        lastFetchedCoordinate = coordinate
        let activities = liveActivities.map(\.activityInput)
        do {
            let result = try await api.fetchRatings(lat: coordinate.latitude,
                                                    lon: coordinate.longitude,
                                                    activities: activities)
            guard generation == loadGeneration else { return }
            forecast = result
            timezoneWarning = timezoneWarningIfNeeded(for: active, forecastTimezone: result.timezone)
            if preferences.lastResolvedLocation != active.savedLocation {
                preferences.lastResolvedLocation = active.savedLocation
            }
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

    /// OK on the alert — remember the home so it never re-warns for it.
    func acknowledgeTimezoneWarning() {
        if let home = preferences.homeLocation {
            preferences.timezoneWarnedHome = home
        }
        timezoneWarning = nil
    }

    /// Home-only: GPS and cached locations track the user, so their clock is
    /// (or was) the device's own. An already-acknowledged home stays quiet.
    private func timezoneWarningIfNeeded(for active: ActiveLocation,
                                         forecastTimezone: String) -> String? {
        guard case .home(let home) = active,
              preferences.timezoneWarnedHome != home,
              let zone = TimeZone(identifier: forecastTimezone) else { return nil }
        return TimezoneMismatch.warning(homeName: home.name,
                                        forecastZone: zone,
                                        deviceZone: deviceTimeZone,
                                        at: Date())
    }

    /// The location chain: home → live GPS fix → last-resolved cache → nil
    /// (nil = show the no-location empty state, never a fallback coordinate).
    private func resolveActiveLocation() -> ActiveLocation? {
        if let home = preferences.homeLocation {
            return .home(home)
        }
        if let fix = locationProvider.location {
            return .gps(fix.coordinate)
        }
        if let cached = preferences.lastResolvedLocation {
            return .cached(cached)
        }
        return nil
    }

    // MARK: authored-activity lookups (icon + nocturnal labels)

    /// The authored source of a response activity, matched by the echoed id.
    func authoredActivity(forActivityId activityId: String) -> AuthoredActivity? {
        store.activities.first { $0.id == activityId }
    }

    /// Explicit icon from the authored model; nil lets the view fall back to
    /// the label heuristic.
    func iconSymbol(forActivityId activityId: String) -> String? {
        authoredActivity(forActivityId: activityId)?.iconSymbol
    }

    /// True when the authored window wraps midnight — the wire never echoes
    /// `window` (ADR-0004 amendment), so nocturnality reads the authored
    /// model; drives the "Tonight"/"… night" day labels.
    func isNocturnal(activityId: String) -> Bool {
        authoredActivity(forActivityId: activityId)?.isNocturnal ?? false
    }

    /// The day bucket the card shows: 0 (today/tonight) — except when the
    /// activity's Range has already fully passed today (no forecast hour left
    /// inside it), where the card falls forward to tomorrow (owner ruling
    /// 2026-09-01). This is deliberately narrower than the cancelled
    /// roll-forward (ADR-0004 amendment): a bad-weather today stays red.
    func cardDayIndex(for authored: AuthoredActivity) -> Int {
        guard let window = authored.window,
              rangeHasPassedToday(window),
              rangeHourIndices(window: window, dayIndex: 1) != nil else {
            return 0
        }
        return 1
    }

    /// The card's day at `dayIndex` (0 today, 1 the passed-range fallback).
    /// Nil when that day has no window — the card renders its none-state; the
    /// week lives in the detail.
    func cardDay(for activity: ActivityRating, dayIndex: Int = 0) -> Day? {
        guard activity.days.indices.contains(dayIndex) else { return nil }
        let day = activity.days[dayIndex]
        return day.rating != nil ? day : nil
    }

    /// The current response's rating for an authored id — keeps a pushed
    /// detail view live across a refetch.
    func rating(forActivityId activityId: String) -> ActivityRating? {
        forecast?.activities.first { $0.activityId == activityId }
    }

    // MARK: Range hours — the client twin of the server's window filter

    /// The global hours[] indices the Activity's Range covers within a day
    /// bucket (a wrapped Range stitches the evening with the next morning —
    /// the morning tail belongs to its evening, ADR-0004 amendment).
    /// Nil when dormant, without a forecast, or when no in-range hour exists.
    func rangeHourIndices(for authored: AuthoredActivity, dayIndex: Int) -> Range<Int>? {
        authored.window.flatMap { rangeHourIndices(window: $0, dayIndex: dayIndex) }
    }

    /// True when a same-day Range has no forecast hour left today — the
    /// forecast starts at the current hour, so an empty day-0 slice means the
    /// Range has fully passed. Drives the card's tomorrow-fallback and the
    /// editor's "already passed" save alert. A wrapped Range never "passes"
    /// (tonight is always ahead of, or inside, the forecast).
    func rangeHasPassedToday(_ window: WindowSpec) -> Bool {
        guard !window.isWrapped, forecast != nil else { return false }
        return rangeHourIndices(window: window, dayIndex: 0) == nil
    }

    /// The forecast hour the editor's review pills read: the Range's first
    /// hour today, or tomorrow once today's Range has passed. Nil without a
    /// forecast — the pills fall back to their neutral name-only state.
    func reviewRangeStartHour(for window: WindowSpec) -> HourlyWeather? {
        guard let hours = forecast?.hours else { return nil }
        let range = rangeHourIndices(window: window, dayIndex: 0)
            ?? rangeHourIndices(window: window, dayIndex: 1)
        return range.map { hours[$0.lowerBound] }
    }

    /// The window-only core of the Range filter — the draft editor has a
    /// WindowSpec before an AuthoredActivity exists.
    func rangeHourIndices(window: WindowSpec, dayIndex: Int) -> Range<Int>? {
        guard let deriver = timeDeriver,
              let hourCount = forecast?.hours.count, hourCount > 0 else {
            return nil
        }
        var lower: Int?
        var upper: Int?
        for index in 0..<hourCount {
            let day = deriver.dayOrdinal(at: index)
            if day > dayIndex + 1 { break }
            let hour = deriver.localHour(at: index)
            let inRange: Bool
            if window.isWrapped {
                inRange = (day == dayIndex && hour >= window.startHour)
                    || (day == dayIndex + 1 && hour < window.endHour)
            } else {
                inRange = day == dayIndex && hour >= window.startHour && hour < window.endHour
            }
            if inRange {
                if lower == nil { lower = index }
                upper = index + 1
            }
        }
        guard let lower, let upper else { return nil }
        return lower..<upper
    }

    /// The forecast hours the Range covers in a day bucket; empty when none.
    func rangeHours(for authored: AuthoredActivity, dayIndex: Int) -> [HourlyWeather] {
        guard let range = rangeHourIndices(for: authored, dayIndex: dayIndex),
              let hours = forecast?.hours else {
            return []
        }
        return Array(hours[range])
    }

    /// Per-hour quality tiers over the Range hours — feeds the card slice's
    /// gradient and the detail's week bars. Empty when none.
    func rangeTiers(for authored: AuthoredActivity, dayIndex: Int) -> [HourTier] {
        rangeHours(for: authored, dayIndex: dayIndex)
            .map { HourQuality.tier(for: $0, thresholds: authored.thresholds) }
    }

    /// The hour at the day's window start — chips read their values here.
    /// startIndex is a global index into hours[].
    func windowStartHour(for day: Day) -> HourlyWeather? {
        guard let startIndex = day.startIndex,
              let hours = forecast?.hours,
              hours.indices.contains(startIndex) else {
            return nil
        }
        return hours[startIndex]
    }

    /// The half-open hours[startIndex..<endIndex] slice for a day's Window;
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
