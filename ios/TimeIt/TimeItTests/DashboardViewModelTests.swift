import XCTest
import Combine
import CoreLocation
@testable import TimeIt

// MARK: - Fakes

final class FakeRatingService: RatingFetching {
    var result: Result<ForecastResponse, Error>
    var onFetch: (@MainActor () -> Void)?
    private(set) var capturedLat: Double?
    private(set) var capturedLon: Double?
    private(set) var capturedActivities: [ActivityInput]?
    private(set) var fetchCount = 0

    init(result: Result<ForecastResponse, Error>) {
        self.result = result
    }

    func fetchRatings(lat: Double, lon: Double, activities: [ActivityInput]) async throws -> ForecastResponse {
        capturedLat = lat
        capturedLon = lon
        capturedActivities = activities
        fetchCount += 1
        if let onFetch {
            await MainActor.run { onFetch() }
        }
        return try result.get()
    }
}

@MainActor
final class FakeLocationProvider: LocationProviding {
    private let subject: CurrentValueSubject<CLLocation?, Never>
    private let authSubject: CurrentValueSubject<CLAuthorizationStatus, Never>

    /// Setting this publishes, like the real manager's @Published property.
    var location: CLLocation? {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var locationPublisher: AnyPublisher<CLLocation?, Never> {
        subject.eraseToAnyPublisher()
    }

    /// Setting this publishes, like the real manager's @Published property.
    var authorizationStatus: CLAuthorizationStatus {
        get { authSubject.value }
        set { authSubject.send(newValue) }
    }

    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        authSubject.eraseToAnyPublisher()
    }

    private(set) var requestLocationCalled = false
    private(set) var requestAuthorizationCalled = false

    init(location: CLLocation? = nil, authorization: CLAuthorizationStatus = .notDetermined) {
        subject = CurrentValueSubject(location)
        authSubject = CurrentValueSubject(authorization)
    }

    func requestLocation() {
        requestLocationCalled = true
    }

    func requestAuthorization() {
        requestAuthorizationCalled = true
    }
}

// MARK: - Tests

@MainActor
final class DashboardViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DashboardViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Default: a real fix + live seeds, so most tests just need a POST to
    /// happen. Chain tests pass `location: nil`; dormancy tests pass seeds.
    private func makeVM(result: Result<ForecastResponse, Error>,
                        location: CLLocation? = CLLocation(latitude: 25.2048, longitude: 55.2708),
                        authorization: CLAuthorizationStatus = .notDetermined,
                        seeds: [AuthoredActivity] = Fixtures.liveSeeds)
        -> (DashboardViewModel, FakeRatingService, FakeLocationProvider, ActivityStore, PreferencesStore) {
        let api = FakeRatingService(result: result)
        let locationProvider = FakeLocationProvider(location: location, authorization: authorization)
        let preferences = PreferencesStore(defaults: defaults)
        let store = ActivityStore(defaults: defaults, seeds: seeds, preferences: preferences)
        let vm = DashboardViewModel(api: api, locationProvider: locationProvider,
                                    store: store, preferences: preferences)
        return (vm, api, locationProvider, store, preferences)
    }

    // MARK: loadForecast

    func testLoadForecastSuccessSetsForecast() async throws {
        let forecast = Fixtures.makeForecast(activities: [Fixtures.makeActivity(days: [Fixtures.makeDay(dayIndex: 0)])])
        let (vm, api, _, _, _) = makeVM(result: .success(forecast))
        api.onFetch = { [weak vm] in
            XCTAssertEqual(vm?.isLoading, true, "isLoading must be true while the request is in flight")
        }

        await vm.loadForecast()

        XCTAssertEqual(vm.forecast?.timezone, "Asia/Dubai")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func testProviderUnavailableMapsToTransientMessage() async {
        let (vm, _, _, _, _) = makeVM(result: .failure(APIError.providerUnavailable))

        await vm.loadForecast()

        XCTAssertNil(vm.forecast)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.errorMessage, APIError.providerUnavailable.userMessage)
        XCTAssertTrue(vm.isTransientError, "a 502 is transient — the UI should suggest retrying")
    }

    func testServerErrorMapsToDistinctMessage() async {
        let (vm, _, _, _, _) = makeVM(result: .failure(APIError.serverError(statusCode: 500)))

        await vm.loadForecast()

        XCTAssertEqual(vm.errorMessage, APIError.serverError(statusCode: 500).userMessage)
        XCTAssertFalse(vm.isTransientError)
        XCTAssertNotEqual(APIError.serverError(statusCode: 500).userMessage,
                          APIError.providerUnavailable.userMessage,
                          "502 and 500 must surface differently")
    }

    func testValidationRejectionSurfacesOffendingActivity() async {
        let error = APIError.validationRejected(message: "\"Stargazing\" was rejected by the server: min greater than max")
        let (vm, _, _, _, _) = makeVM(result: .failure(error))

        await vm.loadForecast()

        XCTAssertEqual(vm.errorMessage, error.userMessage)
        XCTAssertTrue(vm.errorMessage?.contains("Stargazing") == true,
                      "the 400 backstop names the offending Activity (#5b §7)")
        XCTAssertFalse(vm.isTransientError)
    }

    func testConnectionFailureSetsErrorMessage() async {
        let (vm, _, _, _, _) = makeVM(result: .failure(URLError(.cannotConnectToHost)))

        await vm.loadForecast()

        XCTAssertNil(vm.forecast)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: location resolution — home → GPS → lastResolved → none

    func testNoLocationAnywhereSkipsPostAndRaisesSignal() async {
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, api, locationProvider, _, _) = makeVM(result: .success(forecast), location: nil)

        await vm.loadForecast()

        XCTAssertFalse(locationProvider.requestLocationCalled,
                       "not authorized → no fix request from a load (audit F1: the CTA owns onboarding)")
        XCTAssertFalse(locationProvider.requestAuthorizationCalled,
                       "a load must NEVER fire the permission prompt — that would pre-empt the CTA")
        XCTAssertEqual(api.fetchCount, 0, "the Dubai fallback is deleted — a nil chain never POSTs coordinates")
        XCTAssertNil(vm.forecast)
        XCTAssertTrue(vm.hasNoLocation)
        XCTAssertNil(vm.activeLocationName)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: "Enable location" CTA routing

    func testLoadWarmsAFixOnlyWhenAuthorized() async {
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, _, locationProvider, _, _) = makeVM(result: .success(forecast),
                                                     authorization: .authorizedWhenInUse)

        await vm.loadForecast()

        XCTAssertTrue(locationProvider.requestLocationCalled, "authorized loads still warm a fresh fix")
        XCTAssertFalse(locationProvider.requestAuthorizationCalled)
    }

    func testEnableCTAFiresThePromptWhenNotYetAsked() {
        let (vm, _, locationProvider, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])),
                                                     location: nil)

        vm.requestLocationAccess()

        XCTAssertTrue(locationProvider.requestAuthorizationCalled, "not-determined → the system prompt")
        XCTAssertFalse(locationProvider.requestLocationCalled, "no premature fix request before the grant")
    }

    func testEnableCTAWarmsAFixWhenAlreadyAuthorized() {
        let (vm, _, locationProvider, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])),
                                                     location: nil,
                                                     authorization: .authorizedWhenInUse)

        vm.requestLocationAccess()

        XCTAssertTrue(locationProvider.requestLocationCalled, "authorized-but-fixless just needs a fix")
        XCTAssertFalse(locationProvider.requestAuthorizationCalled, "the prompt is a no-op here — don't ask")
    }

    func testDeniedAndRestrictedAreDistinctRoutes() {
        let (deniedVM, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])),
                                            location: nil, authorization: .denied)
        XCTAssertTrue(deniedVM.locationPermissionDenied, "denied → the view deep-links to system Settings")
        XCTAssertFalse(deniedVM.locationPermissionRestricted)

        let (restrictedVM, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])),
                                                location: nil, authorization: .restricted)
        XCTAssertTrue(restrictedVM.locationPermissionRestricted,
                      "restricted (MDM/parental) → honest copy, not a dead-end Settings link (audit F5)")
        XCTAssertFalse(restrictedVM.locationPermissionDenied)
    }

    func testUsesDeviceLocationWhenAvailable() async {
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, api, _, _, _) = makeVM(result: .success(forecast),
                                        location: CLLocation(latitude: 24.4539, longitude: 54.3773))

        await vm.loadForecast()

        XCTAssertEqual(api.capturedLat, 24.4539)
        XCTAssertEqual(api.capturedLon, 54.3773)
    }

    func testHomeLocationWinsOverGPS() async {
        PreferencesStore(defaults: defaults).homeLocation = SavedLocation(name: "Ras Al Khaimah", lat: 25.8007, lon: 55.9762)
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, api, _, _, _) = makeVM(result: .success(forecast),
                                        location: CLLocation(latitude: 24.4539, longitude: 54.3773))

        await vm.loadForecast()

        XCTAssertEqual(api.capturedLat, 25.8007)
        XCTAssertEqual(api.capturedLon, 55.9762)
        XCTAssertEqual(vm.activeLocationName, "Ras Al Khaimah", "the picked city names the header")
    }

    func testGpsWinsOverLastResolvedCache() async {
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, api, _, _, preferences) = makeVM(result: .success(forecast),
                                                  location: CLLocation(latitude: 24.4539, longitude: 54.3773))
        preferences.lastResolvedLocation = SavedLocation(name: "Cached", lat: 10, lon: 10)

        await vm.loadForecast()

        XCTAssertEqual(api.capturedLat, 24.4539, "a live fix beats the cache")
        XCTAssertEqual(vm.activeLocationName, "Current location")
    }

    func testLastResolvedCacheFeedsTheFetchWhenHomeAndGpsAbsent() async {
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, api, _, _, preferences) = makeVM(result: .success(forecast), location: nil)
        preferences.lastResolvedLocation = SavedLocation(name: "Toronto", lat: 43.6532, lon: -79.3832)

        await vm.loadForecast()

        XCTAssertEqual(api.capturedLat, 43.6532)
        XCTAssertEqual(api.capturedLon, -79.3832)
        XCTAssertFalse(vm.hasNoLocation)
        XCTAssertEqual(vm.activeLocationName, "Toronto", "the cached name labels the header")
    }

    // MARK: lastResolved persistence — write on success only

    func testSuccessfulFetchPersistsTheResolvedLocation() async {
        PreferencesStore(defaults: defaults).homeLocation = SavedLocation(name: "Ras Al Khaimah", lat: 25.8007, lon: 55.9762)
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, _, _, _, preferences) = makeVM(result: .success(forecast))

        await vm.loadForecast()

        XCTAssertEqual(preferences.lastResolvedLocation,
                       SavedLocation(name: "Ras Al Khaimah", lat: 25.8007, lon: 55.9762))
        XCTAssertEqual(PreferencesStore(defaults: defaults).lastResolvedLocation?.name, "Ras Al Khaimah",
                       "persisted to defaults, not just in-memory")
    }

    func testGpsFetchPersistsCoordinatesWithNoFabricatedName() async {
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, _, _, _, preferences) = makeVM(result: .success(forecast),
                                                location: CLLocation(latitude: 24.4539, longitude: 54.3773))

        await vm.loadForecast()

        XCTAssertEqual(preferences.lastResolvedLocation?.lat, 24.4539)
        XCTAssertEqual(preferences.lastResolvedLocation?.lon, 54.3773)
        XCTAssertEqual(preferences.lastResolvedLocation?.name, "", "a GPS fix has no place name — none is invented")
    }

    func testFailedFetchDoesNotPersistLastResolved() async {
        let (vm, _, _, _, preferences) = makeVM(result: .failure(APIError.providerUnavailable))

        await vm.loadForecast()

        XCTAssertNil(preferences.lastResolvedLocation, "only a successful rating proves the location works")
    }

    // MARK: activities come from the store

    func testPostsTheLiveStoreActivitiesInOrder() async {
        let (vm, api, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        await vm.loadForecast()

        XCTAssertEqual(api.capturedActivities?.map(\.id), ["cycling", "fishing-lite"],
                       "live activities POST in store order (= card order)")
    }

    // MARK: dormancy — window == nil never reaches any request

    func testDormantActivityIsExcludedFromThePostBody() async {
        let (vm, api, _, store, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])), seeds: [])
        store.add(AuthoredActivity(id: "live", label: "Padel", iconSymbol: "questionmark.circle",
                                   templateOrigin: nil,
                                   displayMetrics: ["temp"],
                                   thresholds: ["temp": Threshold(min: 15, max: 35, required: true)],
                                   window: WindowSpec(startHour: 6, endHour: 10)))
        store.add(AuthoredActivity(id: "dormant", label: "Stargazing", iconSymbol: "moon.stars.fill",
                                   templateOrigin: nil,
                                   displayMetrics: ["cloudCover"],
                                   thresholds: ["cloudCover": Threshold(max: 20, required: true)],
                                   window: nil))

        await vm.loadForecast()

        XCTAssertEqual(api.capturedActivities?.map(\.id), ["live"],
                       "a dormant Activity is stored and visible but can never rate — it must not reach the server window-less")
    }

    func testAllDormantStoreMakesNoRequestAtAll() async {
        let dormantSeeds = SeedTemplates.firstLaunchSeeds.map { seed -> AuthoredActivity in
            var copy = seed
            copy.window = nil
            return copy
        }
        let (vm, api, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])),
                                        seeds: dormantSeeds)

        await vm.loadForecast()

        XCTAssertEqual(api.fetchCount, 0, "an all-dormant dashboard makes no network call (spec 14 §1)")
        XCTAssertNil(vm.forecast)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading, "'Checking conditions…' appears only once ≥1 Activity is live")
        XCTAssertTrue(vm.hasActivities, "dormant activities still exist — this is NOT the empty state")
        XCTAssertFalse(vm.hasLiveActivities)
    }

    func testFirstLaunchSeedsAreDormantAndMakeNoRequest() async {
        let (vm, api, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])),
                                        seeds: SeedTemplates.firstLaunchSeeds)

        await vm.loadForecast()

        XCTAssertEqual(api.fetchCount, 0)
        XCTAssertTrue(vm.hasActivities)
        XCTAssertFalse(vm.hasLiveActivities)
    }

    func testConfirmingARangeOnADormantActivityTriggersTheFirstPost() async {
        let dormantSeeds = SeedTemplates.firstLaunchSeeds.map { seed -> AuthoredActivity in
            var copy = seed
            copy.window = nil
            return copy
        }
        let (vm, api, _, store, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])),
                                            seeds: dormantSeeds)
        await vm.loadForecast()
        XCTAssertEqual(api.fetchCount, 0)

        let refetch = expectation(description: "leaving dormancy triggers the first rating request")
        api.onFetch = { refetch.fulfill() }
        var confirmed = store.activities[0]
        confirmed.window = WindowSpec(startHour: 6, endHour: 10)
        store.update(confirmed)

        await fulfillment(of: [refetch], timeout: 2)
        XCTAssertEqual(api.capturedActivities?.map(\.id), [confirmed.id],
                       "only the now-live Activity POSTs; its dormant sibling stays excluded")
    }

    func testProjectsAuthoredWindowIntoTheRequest() async throws {
        let (vm, api, _, store, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])), seeds: [])
        store.add(AuthoredActivity(id: "n1", label: "Stargazing", iconSymbol: "moon.stars.fill",
                                   templateOrigin: nil,
                                   displayMetrics: ["cloudCover"],
                                   thresholds: ["cloudCover": Threshold(max: 20, required: true)],
                                   window: WindowSpec(startHour: 22, endHour: 4)))

        await vm.loadForecast()

        let sent = try XCTUnwrap(api.capturedActivities?.first)
        XCTAssertEqual(sent.window?.startHour, 22)
        XCTAssertEqual(sent.window?.endHour, 4)
    }

    // MARK: empty-list state — never POST an empty activities[]

    func testEmptyStoreSkipsThePostEntirely() async {
        let (vm, api, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])), seeds: [])

        await vm.loadForecast()

        XCTAssertEqual(api.fetchCount, 0, "ADR-0005 requires non-empty activities — no POST when the list is empty")
        XCTAssertNil(vm.forecast)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.hasActivities)
    }

    func testDeletingAllLiveActivitiesBringsBackTheDormantShowcaseAndStopsPosting() async {
        let (vm, api, _, store, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        XCTAssertTrue(vm.hasActivities)
        store.delete(id: "cycling")
        store.delete(id: "fishing-lite")

        XCTAssertTrue(vm.hasActivities, "the re-seeded showcase is NOT the empty state")
        XCTAssertFalse(vm.hasLiveActivities, "re-seeded cards are dormant")

        await vm.loadForecast()
        XCTAssertEqual(api.fetchCount, 0, "an all-dormant dashboard makes no network call")
    }

    // MARK: store mutations trigger a refetch

    func testStoreMutationTriggersRefetch() async {
        let (vm, api, _, store, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))
        await vm.loadForecast()
        XCTAssertEqual(api.fetchCount, 1)

        let refetch = expectation(description: "store mutation triggers a refetch")
        api.onFetch = { refetch.fulfill() }
        store.add(AuthoredActivity(id: "p1", label: "Padel", iconSymbol: "questionmark.circle",
                                   templateOrigin: nil,
                                   displayMetrics: ["temp"],
                                   thresholds: [:],
                                   window: WindowSpec(startHour: 16, endHour: 19)))

        await fulfillment(of: [refetch], timeout: 2)
        XCTAssertEqual(api.capturedActivities?.map(\.id), ["cycling", "fishing-lite", "p1"])
    }

    func testHomeLocationChangeTriggersRefetch() async {
        let (vm, api, _, _, preferences) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))
        await vm.loadForecast()

        let refetch = expectation(description: "home-location change triggers a refetch")
        api.onFetch = { refetch.fulfill() }
        preferences.homeLocation = SavedLocation(name: "Fujairah", lat: 25.1288, lon: 56.3265)

        await fulfillment(of: [refetch], timeout: 2)
        XCTAssertEqual(api.capturedLat, 25.1288)
    }

    // MARK: late GPS fix — re-rate once when it moves the forecast

    func testFirstFixAfterNoLocationLoadTriggersTheFirstFetch() async {
        let (vm, api, locationProvider, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])),
                                                       location: nil)
        await vm.loadForecast()
        XCTAssertEqual(api.fetchCount, 0, "no location anywhere in the chain → the first load never POSTed")
        XCTAssertTrue(vm.hasNoLocation)

        let fetch = expectation(description: "the first granted fix triggers the first load")
        api.onFetch = { fetch.fulfill() }
        locationProvider.location = CLLocation(latitude: 37.3349, longitude: -122.0090)

        await fulfillment(of: [fetch], timeout: 2)
        XCTAssertEqual(api.capturedLat, 37.3349, "the fetch uses the fresh fix")
    }

    func testGpsFixNearTheFetchedCoordinateDoesNotRefetch() async {
        let (vm, api, locationProvider, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))
        await vm.loadForecast()
        XCTAssertEqual(api.fetchCount, 1, "the first load rates the seeded fix")

        locationProvider.location = CLLocation(latitude: 25.2048, longitude: 55.2708)
        await Task.yield()

        XCTAssertEqual(api.fetchCount, 1, "a fix that doesn't move the forecast must not refetch")
    }

    func testAuthorizationGrantWarmsAFreshFix() {
        let (vm, _, locationProvider, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])),
                                                     location: nil)

        withExtendedLifetime(vm) {
            locationProvider.authorizationStatus = .authorizedWhenInUse
            XCTAssertTrue(locationProvider.requestLocationCalled,
                          "a grant (from the prompt or system Settings) must request a fix so the dashboard revives")
        }
    }

    func testGpsFixWhileHomeLocationSetDoesNotRefetch() async {
        PreferencesStore(defaults: defaults).homeLocation = SavedLocation(name: "Fujairah", lat: 25.1288, lon: 56.3265)
        let (vm, api, locationProvider, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))
        await vm.loadForecast()
        XCTAssertEqual(api.fetchCount, 1)
        XCTAssertEqual(api.capturedLat, 25.1288, "the home location covers the fetch")

        locationProvider.location = CLLocation(latitude: 37.3349, longitude: -122.0090)
        await Task.yield()

        XCTAssertEqual(api.fetchCount, 1,
                       "while a home location covers the fetch, GPS movement is irrelevant")
    }

    // MARK: authored-activity lookups (icon + nocturnal labels)

    func testAuthoredLookupExposesIconAndNocturnality() {
        let (vm, _, _, store, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])), seeds: [])
        store.add(AuthoredActivity(id: "n1", label: "Stargazing", iconSymbol: "moon.stars.fill",
                                   templateOrigin: nil,
                                   displayMetrics: ["cloudCover"],
                                   thresholds: [:],
                                   window: WindowSpec(startHour: 22, endHour: 4)))

        XCTAssertEqual(vm.iconSymbol(forActivityId: "n1"), "moon.stars.fill")
        XCTAssertTrue(vm.isNocturnal(activityId: "n1"))
        XCTAssertFalse(vm.isNocturnal(activityId: "unknown"))
        XCTAssertNil(vm.iconSymbol(forActivityId: "unknown"))
    }

    // MARK: cardDay — day 0 only, no roll-forward (ADR-0004 amendment)

    func testCardDayReturnsDayZeroWhenTodayWindowed() {
        let days = [
            Fixtures.makeDay(dayIndex: 0, rating: "good", startIndex: 1, endIndex: 3, duration: 2),
            Fixtures.makeDay(dayIndex: 1, rating: "perfect", startIndex: 30, endIndex: 35, duration: 5),
        ]
        let (vm, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        let day = vm.cardDay(for: Fixtures.makeActivity(days: days))

        XCTAssertEqual(day?.dayIndex, 0)
        XCTAssertEqual(day?.rating, "good", "day 0 renders as-is — a later Perfect is irrelevant to the card")
    }

    // Guards the cancelled roll-forward (ADR-0004 amendment): the old rule
    // returned dayIndex 2 ("soonest actionable") here.
    func testCardDayReturnsNilWhenTodayNilEvenWithLaterWindows() {
        let days = [
            Fixtures.makeDay(dayIndex: 0),
            Fixtures.makeDay(dayIndex: 1),
            Fixtures.makeDay(dayIndex: 2, rating: "good", startIndex: 52, endIndex: 55, duration: 3),
            Fixtures.makeDay(dayIndex: 3, rating: "perfect", startIndex: 80, endIndex: 90, duration: 10),
        ]
        let (vm, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        XCTAssertNil(vm.cardDay(for: Fixtures.makeActivity(days: days)))
    }

    func testCardDayReturnsNilWhenAllDaysNil() {
        let days = (0..<8).map { Fixtures.makeDay(dayIndex: $0) }
        let (vm, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        XCTAssertNil(vm.cardDay(for: Fixtures.makeActivity(days: days)))
    }

    // MARK: window helpers — global indices, no per-day offset math

    func testWindowStartHourUsesGlobalIndex() async {
        let day = Fixtures.makeDay(dayIndex: 2, rating: "good", startIndex: 52, endIndex: 55, duration: 3)
        let (vm, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [], hourCount: 60)))
        await vm.loadForecast()

        XCTAssertEqual(vm.windowStartHour(for: day)?.index, 52)
    }

    func testWindowStartHourNilWhenNoIndices() async {
        let (vm, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))
        await vm.loadForecast()

        XCTAssertNil(vm.windowStartHour(for: Fixtures.makeDay(dayIndex: 1)))
    }

    func testWindowStartHourNilWhenOutOfRange() async {
        let day = Fixtures.makeDay(dayIndex: 0, rating: "good", startIndex: 99, endIndex: 104, duration: 5)
        let (vm, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [], hourCount: 60)))
        await vm.loadForecast()

        XCTAssertNil(vm.windowStartHour(for: day))
    }

    func testWindowHoursReturnsHalfOpenSlice() async {
        let day = Fixtures.makeDay(dayIndex: 2, rating: "good", startIndex: 52, endIndex: 55, duration: 3)
        let (vm, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [], hourCount: 60)))
        await vm.loadForecast()

        let hours = vm.windowHours(for: day)

        XCTAssertEqual(hours.map(\.index), [52, 53, 54], "endIndex is exclusive")
    }

    func testWindowHoursEmptyWhenIndicesNilOrOutOfRange() async {
        let (vm, _, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [], hourCount: 60)))
        await vm.loadForecast()

        XCTAssertTrue(vm.windowHours(for: Fixtures.makeDay(dayIndex: 0)).isEmpty)
        let outOfRange = Fixtures.makeDay(dayIndex: 0, rating: "good", startIndex: 58, endIndex: 70, duration: 12)
        XCTAssertTrue(vm.windowHours(for: outOfRange).isEmpty)
    }
}
