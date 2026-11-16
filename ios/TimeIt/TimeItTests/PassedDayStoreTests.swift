import XCTest
@testable import TimeIt

/// The client's per-Activity, per-local-date memory of the passed day:
/// the retained morning result (owner ruling 06 a), the card overlay's
/// dismissal and the hours-over row's dismissal. Local, never sent; every
/// key rolls over with the date.
@MainActor
final class PassedDayStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PassedDayStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let perfect = MorningResult(rating: .perfect, window: "7 – 10am")

    func testAFreshDayKnowsNothing() {
        let store = PassedDayStore(defaults: defaults)
        let entry = store.entry(activityId: "cycling", date: "2026-06-19")
        XCTAssertNil(entry.morning)
        XCTAssertFalse(entry.overlayDismissed)
        XCTAssertFalse(entry.rowDismissed)
    }

    func testTheMorningResultIsKeptPerActivityAndDate() {
        let store = PassedDayStore(defaults: defaults)
        store.recordMorning(perfect, activityId: "cycling", date: "2026-06-19")
        XCTAssertEqual(store.entry(activityId: "cycling", date: "2026-06-19").morning, perfect)
        XCTAssertNil(store.entry(activityId: "running", date: "2026-06-19").morning)
    }

    func testTheLastSeenResultWins() {
        let store = PassedDayStore(defaults: defaults)
        store.recordMorning(perfect, activityId: "cycling", date: "2026-06-19")
        let later = MorningResult(rating: .good, window: "8 – 9am")
        store.recordMorning(later, activityId: "cycling", date: "2026-06-19")
        XCTAssertEqual(store.entry(activityId: "cycling", date: "2026-06-19").morning, later)
    }

    func testDismissalsArePerActivityAndPersist() {
        let store = PassedDayStore(defaults: defaults)
        store.dismissOverlay(activityId: "cycling", date: "2026-06-19")
        store.dismissRow(activityId: "running", date: "2026-06-19")

        let reloaded = PassedDayStore(defaults: defaults)
        XCTAssertTrue(reloaded.entry(activityId: "cycling", date: "2026-06-19").overlayDismissed)
        XCTAssertFalse(reloaded.entry(activityId: "cycling", date: "2026-06-19").rowDismissed)
        XCTAssertTrue(reloaded.entry(activityId: "running", date: "2026-06-19").rowDismissed)
        XCTAssertFalse(reloaded.entry(activityId: "running", date: "2026-06-19").overlayDismissed)
    }

    func testEveryKeyRollsOverAtLocalMidnight() {
        let store = PassedDayStore(defaults: defaults)
        store.recordMorning(perfect, activityId: "cycling", date: "2026-06-19")
        store.dismissOverlay(activityId: "cycling", date: "2026-06-19")
        store.dismissRow(activityId: "cycling", date: "2026-06-19")

        let tomorrow = store.entry(activityId: "cycling", date: "2026-06-20")
        XCTAssertNil(tomorrow.morning)
        XCTAssertFalse(tomorrow.overlayDismissed)
        XCTAssertFalse(tomorrow.rowDismissed)
    }

    func testAWriteOnANewDatePrunesTheOldOnes() {
        let store = PassedDayStore(defaults: defaults)
        store.dismissOverlay(activityId: "cycling", date: "2026-06-19")
        store.dismissOverlay(activityId: "cycling", date: "2026-06-20")
        XCTAssertEqual(PassedDayStore(defaults: defaults).storedDates, ["2026-06-20"],
                       "the table never grows past one day")
    }

    func testResetForgetsEverything() {
        let store = PassedDayStore(defaults: defaults)
        store.dismissOverlay(activityId: "cycling", date: "2026-06-19")
        store.reset()
        XCTAssertFalse(PassedDayStore(defaults: defaults).entry(activityId: "cycling", date: "2026-06-19").overlayDismissed)
    }

    // MARK: the hours-over row's "Best was …" line

    func testBestWasLineReadsTheRetainedResult() {
        let line = HoursOverCopy.bestWas(perfect)
        XCTAssertEqual(line?.lead, "Best was 7 – 10am · ")
        XCTAssertEqual(line?.verdict, "Perfect")
        XCTAssertEqual(line?.rating, .perfect)
    }

    func testUnknownMorningFallsBackToTheTitleAlone() {
        XCTAssertNil(HoursOverCopy.bestWas(nil))
        XCTAssertEqual(HoursOverCopy.title, "Today\u{2019}s hours are over")
    }

    func testOverlayCopyNamesTheChosenHours() {
        XCTAssertEqual(HoursOverCopy.overlay(rangeLabel: "6 – 10am"),
                       "Your chosen hours of 6 – 10am have passed, you are seeing tomorrow\u{2019}s score.")
        XCTAssertEqual(HoursOverCopy.overlayHint, "Tap to dismiss")
    }
}

/// The retained morning result is written by the view model whenever it
/// publishes a forecast whose day 0 is rated and not yet over.
@MainActor
final class MorningResultRecordingTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MorningResultRecordingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Forecast starts 2026-06-19T12:00Z = 4pm Dubai. Fishing Lite's 3 – 7pm
    /// Range is under way (index 0 = 4pm, 1 = 5pm); Cycling's 6 – 10am is over.
    private func makeVM(fishingDay0: Day, now: Date) -> (DashboardViewModel, PassedDayStore) {
        let forecast = Fixtures.makeForecast(activities: [
            Fixtures.makeActivity(id: "cycling", days: [
                Day(dayIndex: 0, rating: .perfect, startIndex: 0, endIndex: 1, duration: 1, score: 80),
                Day(dayIndex: 1, rating: .good, startIndex: 15, endIndex: 17, duration: 2, score: 55)]),
            Fixtures.makeActivity(id: "fishing-lite", label: "Fishing Lite", days: [
                fishingDay0, Day(dayIndex: 1, rating: nil, score: 20)]),
        ])
        let passed = PassedDayStore(defaults: defaults)
        let vm = DashboardViewModel(api: FakeRatingService(result: .success(forecast)),
                                    locationProvider: FakeLocationProvider(location: .init(latitude: 25.2, longitude: 55.3)),
                                    store: ActivityStore(defaults: defaults, seeds: Fixtures.liveSeeds),
                                    preferences: PreferencesStore(defaults: defaults),
                                    passedDays: passed,
                                    deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!,
                                    now: { now })
        return (vm, passed)
    }

    private let fourPM = ISO8601DateFormatter().date(from: "2026-06-19T12:00:00Z")!

    func testARatedDayZeroBeforeTheEndIsRetained() async {
        let (vm, passed) = makeVM(fishingDay0: Day(dayIndex: 0, rating: .perfect, startIndex: 0, endIndex: 2,
                                                   duration: 2, score: 90), now: fourPM)
        await vm.loadForecast()
        XCTAssertEqual(passed.entry(activityId: "fishing-lite", date: "2026-06-19").morning,
                       MorningResult(rating: .perfect, window: "4 – 6pm"))
    }

    func testANullDayZeroRetainsNothing() async {
        let (vm, passed) = makeVM(fishingDay0: Day(dayIndex: 0, rating: nil, score: 30), now: fourPM)
        await vm.loadForecast()
        XCTAssertNil(passed.entry(activityId: "fishing-lite", date: "2026-06-19").morning)
    }

    func testADayZeroSeenAfterTheEndIsNotRetained() async {
        let (vm, passed) = makeVM(fishingDay0: Day(dayIndex: 0, rating: .perfect, startIndex: 0, endIndex: 2,
                                                   duration: 2, score: 90), now: fourPM)
        await vm.loadForecast()
        XCTAssertNil(passed.entry(activityId: "cycling", date: "2026-06-19").morning,
                     "Cycling's 6 – 10am was over before this forecast was seen")
    }

    func testCardDayFollowsThePassedRange() async {
        let (vm, _) = makeVM(fishingDay0: Day(dayIndex: 0, rating: nil, score: 30), now: fourPM)
        await vm.loadForecast()
        XCTAssertEqual(vm.shownCardDay(forActivityId: "cycling"), PassedDay.CardDay(passed: true))
        XCTAssertEqual(vm.shownCardDay(forActivityId: "fishing-lite"), PassedDay.CardDay(passed: false))
    }
}
