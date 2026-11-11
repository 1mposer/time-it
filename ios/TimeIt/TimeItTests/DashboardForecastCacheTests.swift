import XCTest
import CoreLocation
@testable import TimeIt

/// Answers every POST with one rating per requested Activity, echoing the
/// request order. Each call stamps its ratings with `score = call number`
/// so a test can tell which POST a card came from. `forecastStart` is
/// settable to simulate the server's hour rolling over between calls.
final class EchoRatingService: RatingFetching {
    var forecastStart = "2026-06-19T12:00:00Z"
    var timezone = "Asia/Dubai"
    var failure: Error?
    private(set) var requests: [[ActivityInput]] = []
    var fetchCount: Int { requests.count }

    func fetchRatings(lat: Double, lon: Double, activities: [ActivityInput]) async throws -> ForecastResponse {
        requests.append(activities)
        if let failure { throw failure }
        let call = requests.count
        return ForecastResponse(
            forecastStart: forecastStart,
            timezone: timezone,
            activities: activities.map {
                ActivityRating(activityId: $0.id, label: $0.label, displayMetrics: $0.displayMetrics,
                               days: [Day(dayIndex: 0, rating: .good, startIndex: 1, endIndex: 3,
                                          duration: 2, score: call)])
            },
            hours: (0..<30).map { Fixtures.makeHour(index: $0, temp: Double(call)) })
    }
}

/// A settable device clock.
final class TestClock {
    var now: Date
    init(_ iso: String) { now = ISO8601DateFormatter().date(from: iso)! }
    func advance(hours: Double) { now = now.addingTimeInterval(hours * 3600) }
}

/// Lane CACHE (owner rules 2026-11-11) through the view-model's public
/// surface: what is drawn (`forecast`) and what reached the server.
@MainActor
final class DashboardForecastCacheTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cacheFile: URL!

    private let dubai = CLLocation(latitude: 25.2048, longitude: 55.2708)
    private let abuDhabi = CLLocation(latitude: 24.4539, longitude: 54.3773)

    override func setUp() {
        super.setUp()
        suiteName = "DashboardForecastCacheTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        cacheFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardForecastCacheTests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: cacheFile)
        super.tearDown()
    }

    private func makeVM(api: EchoRatingService,
                        clock: TestClock,
                        location: CLLocation? = nil,
                        store: ActivityStore? = nil) -> (DashboardViewModel, ActivityStore) {
        let store = store ?? ActivityStore(defaults: defaults, seeds: Fixtures.liveSeeds)
        let vm = DashboardViewModel(api: api,
                                    locationProvider: FakeLocationProvider(location: location ?? dubai),
                                    store: store,
                                    preferences: PreferencesStore(defaults: defaults),
                                    cache: ForecastCache(fileURL: cacheFile),
                                    deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!,
                                    now: { clock.now })
        return (vm, store)
    }

    // MARK: Rule 2 — serve while fresh, refetch when stale / moved / pulled

    func testAReloadWithinThreeHoursServesTheCacheWithoutAPost() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, _) = makeVM(api: api, clock: clock)

        await vm.loadForecast()
        clock.advance(hours: 2.99)
        await vm.loadForecast()

        XCTAssertEqual(api.fetchCount, 1, "a fresh cache answers the foreground return")
        XCTAssertEqual(vm.forecast?.activities.map(\.activityId), ["cycling", "fishing-lite"])
    }

    func testAReloadAtThreeHoursRefetches() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, _) = makeVM(api: api, clock: clock)

        await vm.loadForecast()
        clock.advance(hours: 3)
        await vm.loadForecast()

        XCTAssertEqual(api.fetchCount, 2)
        XCTAssertEqual(vm.forecast?.activities.first?.days.first?.score, 2, "the refetched response is drawn")
    }

    func testALaunchServesTheCacheThePreviousProcessWrote() async {
        let clock = TestClock("2026-06-19T12:10:00Z")
        let firstAPI = EchoRatingService()
        let (first, _) = makeVM(api: firstAPI, clock: clock)
        await first.loadForecast()

        clock.advance(hours: 1)
        let relaunchAPI = EchoRatingService()
        let (relaunched, _) = makeVM(api: relaunchAPI, clock: clock)
        await relaunched.loadForecast()

        XCTAssertEqual(relaunchAPI.fetchCount, 0, "launch reads the disk cache")
        XCTAssertEqual(relaunched.forecast?.activities.first?.days.first?.score, 1)
        XCTAssertEqual(relaunched.forecast?.hours.count, 30)
    }

    func testAChangedLocationKeyRefetches() async {
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (first, _) = makeVM(api: EchoRatingService(), clock: clock, location: dubai)
        await first.loadForecast()

        let api = EchoRatingService()
        let (moved, _) = makeVM(api: api, clock: clock, location: abuDhabi)
        await moved.loadForecast()

        XCTAssertEqual(api.fetchCount, 1, "another 2-dp key is a miss")
    }

    func testPullToRefreshAlwaysBypassesAFreshCache() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, _) = makeVM(api: api, clock: clock)

        await vm.loadForecast()
        clock.advance(hours: 0.1)
        await vm.refresh()

        XCTAssertEqual(api.fetchCount, 2)
        XCTAssertEqual(api.requests.last?.map(\.id), ["cycling", "fishing-lite"], "a pull is a full refetch")
        XCTAssertEqual(vm.forecast?.activities.first?.days.first?.score, 2)
    }

    // MARK: Rule 3 — add/edit POSTs one Activity; delete/reorder never refetch

    /// Store mutations reload through a scheduled task; wait for its effect.
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition never held", file: file, line: line)
    }

    private var padel: AuthoredActivity {
        AuthoredActivity(id: "padel", label: "Padel", iconSymbol: "questionmark.circle", templateOrigin: nil,
                         displayMetrics: ["temp"], thresholds: ["temp": Threshold(min: 18, max: 30, required: true)],
                         window: WindowSpec(startHour: 16, endHour: 19))
    }

    func testEditingOneActivityPostsOnlyItAndMergesItInPlace() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, store) = makeVM(api: api, clock: clock)
        await vm.loadForecast()

        var edited = Fixtures.liveSeeds[0]
        edited.label = "Road Cycling"
        store.update(edited)
        await waitUntil { vm.forecast?.activities.first?.label == "Road Cycling" }

        XCTAssertEqual(api.fetchCount, 2)
        XCTAssertEqual(api.requests.last?.map(\.id), ["cycling"], "only the edited Activity is re-rated")
        XCTAssertEqual(vm.forecast?.activities.map(\.activityId), ["cycling", "fishing-lite"], "merged in place")
        XCTAssertEqual(vm.forecast?.activities.map { $0.days[0].score }, [2, 1],
                       "the edited card reads the new POST, the other keeps its cached rating")
        XCTAssertEqual(vm.forecast?.hours.first?.temp, 1, "the cached hours stay — one forecast, one forecastStart")
        XCTAssertEqual(vm.lastUpdated, ISO8601DateFormatter().date(from: "2026-06-19T12:10:00Z"),
                       "a merge never re-ages the response")
    }

    func testAddingAnActivityPostsOnlyItAndAppendsIt() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, store) = makeVM(api: api, clock: clock)
        await vm.loadForecast()

        store.add(padel)
        await waitUntil { vm.forecast?.activities.count == 3 }

        XCTAssertEqual(api.requests.last?.map(\.id), ["padel"])
        XCTAssertEqual(vm.forecast?.activities.map(\.activityId), ["cycling", "fishing-lite", "padel"])
    }

    func testAMergedEditIsServedFromCacheAfterwards() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, store) = makeVM(api: api, clock: clock)
        await vm.loadForecast()
        store.add(padel)
        await waitUntil { vm.forecast?.activities.count == 3 }

        await vm.loadForecast()

        XCTAssertEqual(api.fetchCount, 2, "the merged entry now matches the store")
    }

    func testAMismatchedForecastStartReplacesTheCacheWithAFullRefetch() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, store) = makeVM(api: api, clock: clock)
        await vm.loadForecast()

        clock.advance(hours: 1)
        api.forecastStart = "2026-06-19T13:00:00Z"
        store.add(padel)
        await waitUntil { vm.forecast?.forecastStart == "2026-06-19T13:00:00Z" }

        XCTAssertEqual(api.fetchCount, 3, "the single POST, then the full refetch")
        XCTAssertEqual(api.requests[1].map(\.id), ["padel"])
        XCTAssertEqual(api.requests[2].map(\.id), ["cycling", "fishing-lite", "padel"])
        XCTAssertEqual(vm.forecast?.activities.map { $0.days[0].score }, [3, 3, 3], "one response, never a mix")
        XCTAssertEqual(vm.lastUpdated, clock.now, "the full refetch re-ages the response")
    }

    func testAMismatchedTimezoneAlsoReplacesTheCache() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, store) = makeVM(api: api, clock: clock)
        await vm.loadForecast()

        api.timezone = "Asia/Muscat"
        store.add(padel)
        await waitUntil { vm.forecast?.timezone == "Asia/Muscat" }

        XCTAssertEqual(api.requests.last?.map(\.id), ["cycling", "fishing-lite", "padel"])
    }

    func testDeletingAnActivityDropsItLocallyWithoutAPost() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, store) = makeVM(api: api, clock: clock)
        await vm.loadForecast()

        store.delete(id: "cycling")
        await waitUntil { vm.forecast?.activities.map(\.activityId) == ["fishing-lite"] }

        XCTAssertEqual(api.fetchCount, 1, "delete never refetches")
        await vm.loadForecast()
        XCTAssertEqual(api.fetchCount, 1, "the pruned entry is what the cache now holds")
    }

    func testMakingAnActivityDormantDropsItLocallyWithoutAPost() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, store) = makeVM(api: api, clock: clock)
        await vm.loadForecast()

        var dormant = Fixtures.liveSeeds[1]
        dormant.window = nil
        store.update(dormant)
        await waitUntil { vm.forecast?.activities.map(\.activityId) == ["cycling"] }

        XCTAssertEqual(api.fetchCount, 1)
    }

    func testAReorderedListReordersTheCacheWithoutAPost() async {
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (first, _) = makeVM(api: EchoRatingService(), clock: clock)
        await first.loadForecast()

        let api = EchoRatingService()
        let reordered = ActivityStore(defaults: UserDefaults(suiteName: "\(suiteName!)-reordered")!,
                                      seeds: Fixtures.liveSeeds.reversed())
        let (vm, _) = makeVM(api: api, clock: clock, store: reordered)
        await vm.loadForecast()

        XCTAssertEqual(api.fetchCount, 0, "reorder never refetches")
        XCTAssertEqual(vm.forecast?.activities.map(\.activityId), ["fishing-lite", "cycling"],
                       "the cards follow the store's order")
        UserDefaults().removePersistentDomain(forName: "\(suiteName!)-reordered")
    }

    func testAnEditToAStaleCacheIsAFullRefetch() async {
        let api = EchoRatingService()
        let clock = TestClock("2026-06-19T12:10:00Z")
        let (vm, store) = makeVM(api: api, clock: clock)
        await vm.loadForecast()

        clock.advance(hours: 4)
        store.add(padel)
        await waitUntil { vm.forecast?.activities.count == 3 }

        XCTAssertEqual(api.fetchCount, 2)
        XCTAssertEqual(api.requests.last?.map(\.id), ["cycling", "fishing-lite", "padel"])
    }
}
