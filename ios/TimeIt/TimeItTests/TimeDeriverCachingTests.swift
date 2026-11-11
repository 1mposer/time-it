import XCTest
import CoreLocation
@testable import TimeIt

/// ROADMAP build-10 deferral (8), absorbed by lane CACHE: the view-model
/// keeps one `TimeDeriver` per forecast instead of rebuilding it (an ISO
/// parser + three DateFormatters) on every read — the detail carousel reads
/// it many times per step.
@MainActor
final class TimeDeriverCachingTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TimeDeriverCachingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeVM(api: EchoRatingService) -> DashboardViewModel {
        let clock = TestClock("2026-06-19T12:10:00Z")
        return DashboardViewModel(api: api,
                                  locationProvider: FakeLocationProvider(
                                      location: CLLocation(latitude: 25.2048, longitude: 55.2708)),
                                  store: ActivityStore(defaults: defaults, seeds: Fixtures.liveSeeds),
                                  preferences: PreferencesStore(defaults: defaults),
                                  cache: ForecastCache(fileURL: nil),
                                  deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!,
                                  now: { clock.now })
    }

    /// 20 000 reads must cost about what 20 000 struct copies do.
    func testTimeDeriverIsBuiltOncePerForecastNotPerRead() async {
        let vm = makeVM(api: EchoRatingService())
        await vm.loadForecast()
        XCTAssertEqual(vm.timeDeriver?.localHour(at: 0), 16, "12:00Z is 4pm in Dubai")

        let start = Date()
        for _ in 0..<20_000 { _ = vm.timeDeriver }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.1, "20 000 reads took \(elapsed) s — the deriver is being rebuilt per read")
    }

    func testTimeDeriverFollowsANewForecastStart() async {
        let api = EchoRatingService()
        let vm = makeVM(api: api)
        await vm.loadForecast()

        api.forecastStart = "2026-06-19T13:00:00Z"
        await vm.refresh()

        XCTAssertEqual(vm.timeDeriver?.localHour(at: 0), 17)
    }

    func testTimeDeriverClearsWithTheForecast() async {
        let vm = makeVM(api: EchoRatingService())
        await vm.loadForecast()
        vm.store.delete(id: "cycling")
        vm.store.delete(id: "fishing-lite")

        await vm.loadForecast()

        XCTAssertNil(vm.forecast)
        XCTAssertNil(vm.timeDeriver)
    }
}
