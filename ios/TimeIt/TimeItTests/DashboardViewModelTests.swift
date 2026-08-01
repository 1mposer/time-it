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

    init(location: CLLocation? = nil, authorization: CLAuthorizationStatus = .notDetermined) {
        subject = CurrentValueSubject(location)
        authSubject = CurrentValueSubject(authorization)
    }

    func requestLocation() {
        requestLocationCalled = true
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

    /// The default location is a real fix — most tests just need a POST to
    /// happen (#5c deleted the Dubai fallback, so a nil location no longer
    /// resolves anywhere). Chain tests pass `location: nil` explicitly.
    private func makeVM(result: Result<ForecastResponse, Error>,
                        location: CLLocation? = CLLocation(latitude: 25.2048, longitude: 55.2708),
                        seeds: [AuthoredActivity] = SeedTemplates.firstLaunchSeeds)
        -> (DashboardViewModel, FakeRatingService, FakeLocationProvider, ActivityStore, PreferencesStore) {
        let api = FakeRatingService(result: result)
        let locationProvider = FakeLocationProvider(location: location)
        let store = ActivityStore(defaults: defaults, seeds: seeds)
        let preferences = PreferencesStore(defaults: defaults)
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

    // MARK: location resolution — home → GPS → lastResolved → none (#5c)

    func testNoLocationAnywhereSkipsPostAndRaisesSignal() async {
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, api, locationProvider, _, _) = makeVM(result: .success(forecast), location: nil)

        await vm.loadForecast()

        XCTAssertTrue(locationProvider.requestLocationCalled, "the load still warms a fix — it's the recovery path")
        XCTAssertEqual(api.fetchCount, 0, "the Dubai fallback is deleted — a nil chain never POSTs coordinates")
        XCTAssertNil(vm.forecast)
        XCTAssertTrue(vm.hasNoLocation)
        XCTAssertNil(vm.activeLocationName)
        XCTAssertFalse(vm.isLoading)
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
        // Seeded before the VM exists so the home-change sink can't spawn an
        // orphan load that outlives the test (see the persistence test below).
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

    // MARK: lastResolved persistence — write on success only (#5c)

    func testSuccessfulFetchPersistsTheResolvedLocation() async {
        // Persist the home BEFORE the VM exists — mutating it afterwards would
        // fire the home-change refetch sink, whose unawaited load supersedes
        // this one (generation guard) and races the assertions.
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

    func testPostsTheStoreActivitiesOnFirstLaunch() async {
        let (vm, api, _, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        await vm.loadForecast()

        XCTAssertEqual(api.capturedActivities?.map(\.id), ["cycling", "fishing-lite"],
                       "first launch POSTs the seeded Templates — identical to the #5a dashboard")
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

    func testHasActivitiesReflectsStore() {
        let (vm, _, _, store, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        XCTAssertTrue(vm.hasActivities)
        store.delete(id: "cycling")
        store.delete(id: "fishing-lite")
        XCTAssertFalse(vm.hasActivities)
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
                                   window: nil))

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
        // #5c: the no-location empty state never POSTed, so lastFetchedCoordinate
        // is nil — the first granted fix must count as a meaningful move, not be
        // silently discarded (acceptance §3.3).
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

        // Every load calls requestLocation(), so a same-place fix arrives after
        // every fetch — refetching on it would loop request→fix→request forever.
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
        // Persist the home BEFORE the VM exists — mutating it afterwards would
        // trigger the home-change refetch sink and race this test.
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

    // MARK: cardDay — day 0 only, no roll-forward (ADR-0004 amendment 2026-07-20)

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

    func testCardDayReturnsNilWhenTodayNilEvenWithLaterWindows() {
        // The cancellation's regression test: under the old rule this returned
        // dayIndex 2 (the "soonest-actionable" roll-forward). The card must now
        // ignore later days entirely — the week lives in the detail timeline.
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
