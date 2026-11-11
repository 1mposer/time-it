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
}
