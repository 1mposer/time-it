import Combine
import CoreLocation
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var forecast: ForecastResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// #5c: true when the Active-location chain resolved to nothing — the
    /// dashboard shows the no-location empty state (grayed cards + the two
    /// location CTAs). Distinct from `!hasActivities`, which is a different
    /// screen.
    @Published private(set) var hasNoLocation = false
    /// #5c: what the header's location line shows for the Active location —
    /// the picked city name, "Current location", or the cached name. nil when
    /// the chain resolved to nothing.
    @Published private(set) var activeLocationName: String?

    /// True when the last failure is worth retrying (502 / unreachable server),
    /// as opposed to a server defect (500). Drives the error view's framing.
    private(set) var isTransientError = false

    private let api: RatingFetching
    private let locationProvider: LocationProviding
    /// Exposed so views mutate and observe the SAME store the requests are
    /// built from — a separately-injected copy would silently diverge.
    let store: ActivityStore
    /// Exposed for the same reason as `store`: the city-picker sheet must
    /// write to the SAME preferences the requests resolve from.
    let preferences: PreferencesStore
    private var cancellables: Set<AnyCancellable> = []
    /// Monotonic guard: only the newest in-flight load may publish its result,
    /// so a slow pre-mutation response can't overwrite a newer one.
    private var loadGeneration = 0
    /// The coordinate the most recent POST actually used. Lets a late GPS fix
    /// trigger a reload only when it would move the forecast location — the
    /// distance gate is what prevents a request→fix→request loop, since every
    /// load calls requestLocation() and every fix lands back in the sink below.
    /// nil = no POST has happened yet, so any first fix is a meaningful move
    /// (#5c: the no-location empty state must react to the first grant).
    private var lastFetchedCoordinate: CLLocationCoordinate2D?

    /// Where the Active-location chain resolved (#5c): home → GPS →
    /// last-resolved cache. Drives the POST coordinate, the header label, and
    /// what gets persisted back to the cache on success.
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

        /// What a successful fetch writes to `lastResolvedLocation`. A GPS fix
        /// has no known place name — persist empty rather than fabricate one.
        var savedLocation: SavedLocation {
            switch self {
            case .home(let saved), .cached(let saved):
                return saved
            case .gps(let coordinate):
                return SavedLocation(name: "", lat: coordinate.latitude, lon: coordinate.longitude)
            }
        }
    }

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
        // requestLocation() resolves AFTER the load that called it, so the
        // first fix usually arrives once a forecast (or the no-location empty
        // state) is already on screen. Re-rate exactly then — but only while
        // no home location overrides GPS, and only when the fix actually moves
        // the forecast somewhere new. A fix with no prior POST is always a
        // meaningful move (#5c) — that's how granting access revives the
        // empty state. dropFirst skips the subscription replay so a seeded
        // provider doesn't race the view's initial load.
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
        // #5c: a grant (from the prompt, or from system Settings after a
        // denial) warms a fresh fix; the fix then lands in the sink above.
        // removeDuplicates BEFORE dropFirst: CLLocationManager always fires
        // one no-change callback shortly after creation — deduping it against
        // the replayed seed (then dropping the seed) keeps this sink to
        // genuine status changes instead of a spurious GPS spin-up per launch.
        self.locationProvider.authorizationPublisher
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] status in
                guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
                self?.locationProvider.requestLocation()
            }
            .store(in: &cancellables)

        // Seed the header label synchronously — the first load runs from the
        // view's .task, one frame later, and a user with a resolvable
        // location must not see a "NO LOCATION" flash on launch.
        activeLocationName = resolveActiveLocation()?.displayName
    }

    /// Reload off a state change. Bumps the generation BEFORE scheduling —
    /// the scheduled load's own increment happens only when the task runs, a
    /// window in which an in-flight load's response could still publish (and
    /// write a stale location into the cache).
    private func scheduleReload() {
        loadGeneration += 1
        Task { await loadForecast() }
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

    /// Spec 14 §1: only LIVE activities (confirmed Range) are ever sent — a
    /// dormant Activity is stored and visible but excluded from every request.
    var liveActivities: [AuthoredActivity] { store.activities.filter { !$0.isDormant } }

    /// False when nothing is live (store empty OR all-dormant): no request is
    /// made and "Checking conditions…" never shows (spec 14 §1).
    var hasLiveActivities: Bool { !liveActivities.isEmpty }

    /// #5c: true when "Enable location" should deep-link to system Settings
    /// instead of firing the (now impossible) permission prompt.
    var locationPermissionDenied: Bool {
        locationProvider.authorizationStatus == .denied
    }

    /// #5c audit F5: restricted (parental controls / MDM) users CANNOT toggle
    /// the switch — deep-linking them to Settings is a dead end, so the view
    /// shows honest copy instead of the CTA.
    var locationPermissionRestricted: Bool {
        locationProvider.authorizationStatus == .restricted
    }

    private var isAuthorized: Bool {
        locationProvider.authorizationStatus == .authorizedWhenInUse
            || locationProvider.authorizationStatus == .authorizedAlways
    }

    /// #5c: the "Enable location" CTA. Not-yet-asked → fire the system prompt
    /// (audit F1: the prompt belongs HERE, never to a load); already
    /// authorized but fixless → just warm a fix. The denied case never
    /// reaches this — the view deep-links to system Settings instead.
    func requestLocationAccess() {
        if isAuthorized {
            locationProvider.requestLocation()
        } else {
            locationProvider.requestAuthorization()
        }
    }

    func loadForecast() async {
        loadGeneration += 1
        let generation = loadGeneration

        guard hasLiveActivities else {
            // Never POST an empty activities[] (ADR-0005), and an all-dormant
            // dashboard makes no network call (spec 14 §1). Still resolve the
            // chain so the header label and the no-location flag stay
            // truthful (different screens, but one shared header).
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

        // Warm the GPS fix on every load (even while a home location covers
        // this fetch) — but ONLY when already authorized. Requesting without
        // authorization used to fire the permission prompt at launch, before
        // the empty state's CTA ever rendered (audit F1); now the CTA owns
        // the prompt and this is a pure fix refresh. The request resolves
        // asynchronously — this load proceeds with whatever the chain
        // resolves now; the locationPublisher sink re-rates once a fresh fix
        // lands somewhere new.
        if isAuthorized {
            locationProvider.requestLocation()
        }

        guard let active = resolveActiveLocation() else {
            // #5c: the chain resolved to nothing — no POST, no fabricated
            // coordinates. The empty state's CTAs are the way forward.
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
        // Spec 14 §1: dormant activities never reach the wire.
        let activities = liveActivities.map(\.activityInput)
        do {
            let result = try await api.fetchRatings(lat: coordinate.latitude,
                                                    lon: coordinate.longitude,
                                                    activities: activities)
            guard generation == loadGeneration else { return }
            forecast = result
            // #5c: remember what actually worked — the launch-with-nothing
            // case rates against this instead of going empty. Skip when
            // unchanged: the write churns defaults + every store observer.
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

    /// The Active-location chain (#5c): home → live GPS fix → last-resolved
    /// cache → nil. The Dubai fallback is deleted — nil means "show the
    /// no-location empty state", never a substitute coordinate.
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
