import XCTest
import CoreLocation
@testable import TimeIt

/// Spec 14 §2/§7 plumbing: which global hours[] indices an Activity's Range
/// covers within a day bucket (the client twin of the server's window filter
/// and night-stitch selection), the per-hour tiers over them (HourQuality),
/// and the card phrase rule. Fixture zone: forecastStart 2026-06-19T12:00:00Z
/// in Asia/Dubai (+04) → hours[0] is 4pm local; day 0 spans indices 0..<8,
/// day 1 spans 8..<32, day 2 spans 32..<56.
@MainActor
final class RangeWindowTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "RangeWindowTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeLoadedVM(hours: [HourlyWeather]? = nil) async -> DashboardViewModel {
        let forecast = ForecastResponse(forecastStart: "2026-06-19T12:00:00Z",
                                        timezone: "Asia/Dubai",
                                        activities: [],
                                        hours: hours ?? (0..<60).map { Fixtures.makeHour(index: $0) })
        let preferences = PreferencesStore(defaults: defaults)
        let store = ActivityStore(defaults: defaults, seeds: Fixtures.liveSeeds, preferences: preferences)
        let vm = DashboardViewModel(api: FakeRatingService(result: .success(forecast)),
                                    locationProvider: FakeLocationProvider(location: CLLocation(latitude: 25.2, longitude: 55.27)),
                                    store: store, preferences: preferences)
        await vm.loadForecast()
        return vm
    }

    private func makeActivity(window: WindowSpec?,
                              thresholds: [String: Threshold] = [:]) -> AuthoredActivity {
        AuthoredActivity(id: "a1", label: "A", iconSymbol: "questionmark.circle",
                         templateOrigin: nil, displayMetrics: ["temp"],
                         thresholds: thresholds, window: window)
    }

    // MARK: TimeDeriver.localHour — the client twin of the server's internal tag

    func testLocalHourDerivesInTheLocationZone() throws {
        let deriver = try XCTUnwrap(TimeDeriver(forecastStart: "2026-06-19T12:00:00Z",
                                                timezone: "Asia/Dubai"))
        XCTAssertEqual(deriver.localHour(at: 0), 16, "12:00Z is 4pm in Asia/Dubai")
        XCTAssertEqual(deriver.localHour(at: 8), 0, "index 8 is midnight — day 1 starts")
        XCTAssertEqual(deriver.localHour(at: 14), 6)
    }

    // MARK: rangeHourIndices — diurnal

    func testDiurnalRangeOnAFullDay() async {
        let vm = await makeLoadedVM()
        let activity = makeActivity(window: WindowSpec(startHour: 6, endHour: 10))

        XCTAssertEqual(vm.rangeHourIndices(for: activity, dayIndex: 1), 14..<18,
                       "day 1 starts at index 8 (midnight); 6–10am is indices 14..<18 — global, not day-relative")
    }

    func testDiurnalRangeClampsToThePartialDayZero() async {
        // The forecast starts 4pm local: a 3–7pm range has only 4–7pm left today.
        let vm = await makeLoadedVM()
        let activity = makeActivity(window: WindowSpec(startHour: 15, endHour: 19))

        XCTAssertEqual(vm.rangeHourIndices(for: activity, dayIndex: 0), 0..<3)
    }

    func testDiurnalRangeFullyPastOnDayZeroIsNil() async {
        // 6–10am is over by 4pm — nothing in range exists today. The card
        // paints nothing (empty track), never fabricated hours.
        let vm = await makeLoadedVM()
        let activity = makeActivity(window: WindowSpec(startHour: 6, endHour: 10))

        XCTAssertNil(vm.rangeHourIndices(for: activity, dayIndex: 0))
    }

    // MARK: rangeHourIndices — nocturnal night-stitch (evening-keyed)

    func testNocturnalRangeStitchesEveningWithNextMorning() async {
        let vm = await makeLoadedVM()
        let activity = makeActivity(window: WindowSpec(startHour: 22, endHour: 4))

        XCTAssertEqual(vm.rangeHourIndices(for: activity, dayIndex: 0), 6..<12,
                       "night 0 = tonight 10pm–midnight (6..<8) + tomorrow morning 12–4am (8..<12)")
        XCTAssertEqual(vm.rangeHourIndices(for: activity, dayIndex: 1), 30..<36,
                       "night 1 keys on tomorrow evening — the morning tail belongs to its evening")
    }

    // MARK: rangeHourIndices — guards

    func testDormantActivityHasNoRangeIndices() async {
        let vm = await makeLoadedVM()
        XCTAssertNil(vm.rangeHourIndices(for: makeActivity(window: nil), dayIndex: 0))
    }

    func testRangeBeyondTheHorizonIsNil() async {
        let vm = await makeLoadedVM()
        let activity = makeActivity(window: WindowSpec(startHour: 6, endHour: 10))
        XCTAssertNil(vm.rangeHourIndices(for: activity, dayIndex: 9),
                     "no hours exist for a day past the horizon")
    }

    // MARK: rangeTiers — the HourQuality mirror over the range hours

    func testRangeTiersReflectPerHourQuality() async {
        // Day 1's 6–10am spans indices 14..<18. Hour 15 fails an optional
        // threshold (orange), hour 16 fails a required one (red) — the
        // truthful zigzag must survive per-hour.
        var hours = (0..<60).map { Fixtures.makeHour(index: $0) }
        hours[15] = Fixtures.makeHour(index: 15, windSpeed: 40)
        hours[16] = Fixtures.makeHour(index: 16, temp: 45)
        let vm = await makeLoadedVM(hours: hours)
        let activity = makeActivity(window: WindowSpec(startHour: 6, endHour: 10),
                                    thresholds: ["temp": Threshold(min: 15, max: 32, required: true),
                                                 "windSpeed": Threshold(max: 25, required: false)])

        XCTAssertEqual(vm.rangeTiers(for: activity, dayIndex: 1),
                       [.green, .orange, .red, .green])
    }

    func testRangeTiersEmptyWhenNoRangeHoursExist() async {
        let vm = await makeLoadedVM()
        let activity = makeActivity(window: WindowSpec(startHour: 6, endHour: 10))
        XCTAssertTrue(vm.rangeTiers(for: activity, dayIndex: 0).isEmpty)
    }

    // MARK: cardPhrase — §2 all-bad copy is unconditional; §5 gates the rest

    func testUnratedDayAlwaysReadsNothingInYourRange() {
        // The all-red day's phrase is part of the state (approved Loaded frame
        // 111:2 shows it with phrases OFF), not gated by the §5 toggle.
        XCTAssertEqual(TrajectoryPhrase.cardPhrase(dayRated: false, tiers: [], phrasesEnabled: false),
                       "Nothing in your range")
        XCTAssertEqual(TrajectoryPhrase.cardPhrase(dayRated: false, tiers: [.green], phrasesEnabled: true),
                       "Nothing in your range",
                       "server rating is truth — a mirror disagreement never rewrites the all-bad copy")
    }

    func testRatedDayPhraseIsGatedByTheToggle() {
        XCTAssertNil(TrajectoryPhrase.cardPhrase(dayRated: true, tiers: [.green, .green], phrasesEnabled: false),
                     "default off — the card carries quality in color alone")
        XCTAssertEqual(TrajectoryPhrase.cardPhrase(dayRated: true, tiers: [.orange, .green], phrasesEnabled: true),
                       "Good, turning perfect")
    }
}
