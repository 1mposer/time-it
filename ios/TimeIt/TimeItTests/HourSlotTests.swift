import XCTest
import CoreLocation
@testable import TimeIt

/// Owner ruling 2026-11-04 — gone hours are drawn, grey, with no weather.
/// The forecast starts at the current hour, so a Range that began before it
/// used to lose its early hours on both the card strip and the detail row.
/// Both now read the FULL authored Range as day-local hour SLOTS: a slot
/// before `hours[0]` carries `index == nil` (no data) and renders passed.
@MainActor
final class HourSlotTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HourSlotTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Asia/Dubai is UTC+4 with no DST: `forecastStart` 04:00Z = 8am local.
    private func makeLoadedVM(forecastStart: String, hourCount: Int = 40) async -> DashboardViewModel {
        let forecast = ForecastResponse(forecastStart: forecastStart,
                                        timezone: "Asia/Dubai",
                                        activities: [],
                                        hours: (0..<hourCount).map { Fixtures.makeHour(index: $0) })
        let preferences = PreferencesStore(defaults: defaults)
        let store = ActivityStore(defaults: defaults, seeds: Fixtures.liveSeeds)
        let vm = DashboardViewModel(api: FakeRatingService(result: .success(forecast)),
                                    locationProvider: FakeLocationProvider(location: CLLocation(latitude: 25.2, longitude: 55.27)),
                                    store: store, preferences: preferences)
        await vm.loadForecast()
        return vm
    }

    private func activity(_ window: WindowSpec) -> AuthoredActivity {
        AuthoredActivity(id: "a1", label: "A", iconSymbol: "questionmark.circle",
                         templateOrigin: nil, displayMetrics: ["temp"],
                         thresholds: ["temp": Threshold(min: 15, max: 32, required: true)],
                         window: window)
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: Slot derivation

    func testRangeStartedBeforeTheForecastKeepsItsGoneHours() async {
        // 8am start, 6–10am Range: 6 and 7 are gone (no data), 8 and 9 are
        // hours[0] and hours[1].
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T04:00:00Z")
        let authored = activity(WindowSpec(startHour: 6, endHour: 10))
        let slots = vm.rangeSlots(for: authored, dayIndex: 0)

        XCTAssertEqual(slots.map(\.localHour), [6, 7, 8, 9])
        XCTAssertEqual(slots.map(\.index), [nil, nil, 0, 1])
        XCTAssertEqual(slots.map(\.position), [-2, -1, 0, 1],
                       "positions continue the global index space backwards")
        XCTAssertEqual(vm.rangeSlotPositions(for: authored, dayIndex: 0), -2..<2)
    }

    func testWrappedRangeStartedBeforeTheForecastKeepsItsGoneEvening() async {
        // 11pm start, 10pm–2am Range: 10pm is gone; 11pm, 12am, 1am are data.
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T19:00:00Z")
        let slots = vm.rangeSlots(for: activity(WindowSpec(startHour: 22, endHour: 2)), dayIndex: 0)

        XCTAssertEqual(slots.map(\.localHour), [22, 23, 0, 1])
        XCTAssertEqual(slots.map(\.index), [nil, 0, 1, 2],
                       "the morning tail is attributed to its evening (night 0)")
    }

    func testWrappedRangeOnALaterNightIsAllData() async {
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T19:00:00Z")
        let slots = vm.rangeSlots(for: activity(WindowSpec(startHour: 22, endHour: 2)), dayIndex: 1)
        XCTAssertEqual(slots.map(\.localHour), [22, 23, 0, 1])
        XCTAssertEqual(slots.map(\.index), [23, 24, 25, 26])
    }

    func testRangeThatEndedBeforeTheForecastIsAllGone() async {
        // 2pm start: the whole 6–10am Range is behind us, still drawn.
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T10:00:00Z")
        let authored = activity(WindowSpec(startHour: 6, endHour: 10))
        let slots = vm.rangeSlots(for: authored, dayIndex: 0)

        XCTAssertEqual(slots.map(\.localHour), [6, 7, 8, 9])
        XCTAssertEqual(slots.map(\.index), [nil, nil, nil, nil])
        XCTAssertNil(vm.rangeHourIndices(for: authored, dayIndex: 0),
                     "the data-only Range (editor's passed alert) is unchanged")
    }

    func testNoWindowHasNoSlots() async {
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T04:00:00Z")
        let dormant = AuthoredActivity(id: "d", label: "D", iconSymbol: "questionmark.circle",
                                       templateOrigin: nil, displayMetrics: ["temp"],
                                       thresholds: [:], window: nil)
        XCTAssertTrue(vm.rangeSlots(for: dormant, dayIndex: 0).isEmpty)
        XCTAssertNil(vm.rangeSlotPositions(for: dormant, dayIndex: 0))
    }

    // MARK: Card strip

    func testCardStripGreysGoneHoursAndColoursTheRest() async {
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T04:00:00Z")
        // 8:30am local: 6 and 7 are gone, 8 is under way (not passed).
        let tiers = vm.rangeStripTiers(for: activity(WindowSpec(startHour: 6, endHour: 10)),
                                       dayIndex: 0,
                                       now: date("2026-06-19T04:30:00Z"))
        XCTAssertEqual(tiers, [nil, nil, .green, .green], "nil = the grey passed / no-data segment")
    }

    func testCardStripGreysAPassedHourEvenWithData() async {
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T04:00:00Z")
        // 9:15am: hours[0] (8am) has data but has ended.
        let tiers = vm.rangeStripTiers(for: activity(WindowSpec(startHour: 6, endHour: 10)),
                                       dayIndex: 0,
                                       now: date("2026-06-19T05:15:00Z"))
        XCTAssertEqual(tiers, [nil, nil, nil, .green])
    }

    // MARK: Carousel walk

    func testWalkableCoversTheGoneRangeHoursAndTheRestOfTheDay() async {
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T04:00:00Z")
        let authored = activity(WindowSpec(startHour: 6, endHour: 10))
        // Day 0's data runs 8am..midnight = indices 0..<16; the Range adds -2, -1.
        XCTAssertEqual(vm.walkableHourRange(for: authored, dayIndex: 0), -2..<16)

        let carousel = HourCarousel(walkable: -2..<16,
                                    rangeHours: vm.rangeSlotPositions(for: authored, dayIndex: 0),
                                    visibleSlots: 6)
        XCTAssertEqual(carousel.span, -2..<2, "the row opens on the FULL Range")
        XCTAssertTrue(carousel.isAtRange)
        XCTAssertEqual(vm.slots(in: carousel.span).map(\.localHour), [6, 7, 8, 9])
        XCTAssertEqual(vm.slots(in: carousel.span).map(\.index), [nil, nil, 0, 1])
    }

    func testWrappedWalkableReachesBackToTheGoneEvening() async {
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T19:00:00Z")
        let authored = activity(WindowSpec(startHour: 22, endHour: 2))
        // Day 0 data = 11pm only (index 0); the Range spans -1..<3.
        XCTAssertEqual(vm.walkableHourRange(for: authored, dayIndex: 0), -1..<3)
    }

    // MARK: Aggregate over slots

    func testAggregateOverGoneHoursUsesTheDataHoursOnly() {
        var hours = (0..<4).map { Fixtures.makeHour(index: $0) }
        hours[0] = Fixtures.makeHour(index: 0, temp: 20)
        hours[1] = Fixtures.makeHour(index: 1, temp: 26)
        let slots = [HourSlot(position: -2, localHour: 6, index: nil),
                     HourSlot(position: -1, localHour: 7, index: nil),
                     HourSlot(position: 0, localHour: 8, index: 0),
                     HourSlot(position: 1, localHour: 9, index: 1)]
        let result = HourAggregate.aggregate(slots: slots, hours: hours)
        XCTAssertEqual(result?.temp, 23, "(20 + 26) / 2 — the gone slots are not zeros")
        XCTAssertEqual(result?.index, 0)
    }

    func testAggregateOverAnAllGoneSpanIsNil() {
        let hours = (0..<4).map { Fixtures.makeHour(index: $0) }
        let slots = [HourSlot(position: -2, localHour: 6, index: nil),
                     HourSlot(position: -1, localHour: 7, index: nil)]
        XCTAssertNil(HourAggregate.aggregate(slots: slots, hours: hours), "the cards show —")
    }

    // MARK: TimeDeriver slot mapping

    func testSlotMapsPositionsOutsideTheForecastToNoIndex() throws {
        let deriver = try XCTUnwrap(TimeDeriver(forecastStart: "2026-06-19T04:00:00Z", timezone: "Asia/Dubai"))
        XCTAssertEqual(deriver.slot(at: -1, hourCount: 3), HourSlot(position: -1, localHour: 7, index: nil))
        XCTAssertEqual(deriver.slot(at: 2, hourCount: 3), HourSlot(position: 2, localHour: 10, index: 2))
        XCTAssertEqual(deriver.slot(at: 3, hourCount: 3), HourSlot(position: 3, localHour: 11, index: nil),
                       "past the horizon has no data either")
    }

    // MARK: Pull-to-refresh keeps the list on screen

    func testRefreshKeepsTheListMountedWhileItFetches() async {
        let vm = await makeLoadedVM(forecastStart: "2026-06-19T04:00:00Z")
        XCTAssertNotNil(vm.forecast)
        let api = FakeRatingService(result: .success(vm.forecast!))
        let preferences = PreferencesStore(defaults: defaults)
        let store = ActivityStore(defaults: defaults, seeds: Fixtures.liveSeeds)
        let refreshing = DashboardViewModel(api: api,
                                            locationProvider: FakeLocationProvider(location: CLLocation(latitude: 25.2, longitude: 55.27)),
                                            store: store, preferences: preferences)
        await refreshing.loadForecast()
        var loadingMidFetch: Bool?
        api.onFetch = { loadingMidFetch = refreshing.isLoading }
        await refreshing.refresh()
        XCTAssertEqual(loadingMidFetch, false,
                       "a pull keeps the card list (and its refresh control) mounted — no full-screen spinner")
        XCTAssertEqual(api.fetchCount, 2, "the pull refetches (there is no client cache)")
        XCTAssertNotNil(refreshing.forecast)
    }
}

/// The detail hero's geometry (owner ruling 2026-11-04): ring 64, the line
/// under the row, the height is the taller column plus the insets.
final class DetailHeroLayoutTests: XCTestCase {
    func testRingIs64WithA24NumeralAndA5Stroke() {
        XCTAssertEqual(Theme.Detail.ringDiameter, 64)
        XCTAssertEqual(Theme.Detail.ringNumeral, 24)
        XCTAssertEqual(Theme.Detail.ringStroke, 5)
        XCTAssertEqual(Theme.Detail.ringColumnHeight, 64 + 12 + 14)
    }

    func testHeroHeightIsTheTallerColumnPlusInsets() {
        XCTAssertEqual(Theme.Detail.rowColumnHeight(hasLine: false), 24)
        XCTAssertEqual(Theme.Detail.rowColumnHeight(hasLine: true), 24 + 8 + 24)
        XCTAssertEqual(Theme.Detail.heroHeight(hasLine: false), 122, "16 + 64 + 12 + 14 + 16")
        XCTAssertEqual(Theme.Detail.heroHeight(hasLine: true), 122,
                       "the row + line block (56) is shorter than the ring column (90)")
    }

    func testRowBlockCentresOnTheRingColumn() {
        // No line: the row sits on the ring's centre line (32 − 12 = 20).
        XCTAssertEqual(Theme.Detail.rowColumnTop(hasLine: false), 20)
        // Line: the 56pt block centres on the 90pt column ((90 − 56) / 2).
        XCTAssertEqual(Theme.Detail.rowColumnTop(hasLine: true), 17)
    }
}

/// The line under the detail row: "Your range …" on the Range, "Showing …"
/// plus the return button away from it. Uses `RangeText.chipLabel`, so the
/// am/pm rules match the card chip and the server's clock labels.
final class RangeLineTests: XCTestCase {
    private let window = WindowSpec(startHour: 6, endHour: 10)

    func testOnTheRangeReadsYourRangeWithNoReturn() {
        let line = RangeLine(window: window, isAtRange: true, spanStartHour: 6, spanEndHour: 10)
        XCTAssertEqual(line.text, "Your range 6 – 10am")
        XCTAssertFalse(line.showsReturn)
    }

    func testAwayReadsShowingTheSpanWithReturn() {
        let line = RangeLine(window: window, isAtRange: false, spanStartHour: 7, spanEndHour: 11)
        XCTAssertEqual(line.text, "Showing 7 – 11am")
        XCTAssertTrue(line.showsReturn)
    }

    func testAwayAcrossNoonKeepsBothSuffixes() {
        let line = RangeLine(window: window, isAtRange: false, spanStartHour: 8, spanEndHour: 12)
        XCTAssertEqual(line.text, "Showing 8am – 12pm", "chipLabel's meridiem rule, not a new format")
    }

    func testWrappedRangeOnAndAway() {
        let night = WindowSpec(startHour: 22, endHour: 2)
        XCTAssertEqual(RangeLine(window: night, isAtRange: true, spanStartHour: 22, spanEndHour: 2).text,
                       "Your range 10pm – 2am")
        XCTAssertEqual(RangeLine(window: night, isAtRange: false, spanStartHour: 23, spanEndHour: 3).text,
                       "Showing 11pm – 3am")
    }

    // MARK: "Time passed" (owner ruling 2026-11-04)

    func testOnAPassedRangeReadsTimePassedOnTheSameLine() {
        let line = RangeLine(window: window, isAtRange: true, spanStartHour: 6, spanEndHour: 10,
                             rangeHasPassed: true)
        XCTAssertEqual(line.text, "Your range 6 – 10am · Time passed")
        XCTAssertFalse(line.showsReturn)
    }

    func testOnARangeStillAheadHasNoTimePassed() {
        let line = RangeLine(window: window, isAtRange: true, spanStartHour: 6, spanEndHour: 10,
                             rangeHasPassed: false)
        XCTAssertEqual(line.text, "Your range 6 – 10am")
    }

    func testAwayFromAPassedRangeStillReadsShowing() {
        let line = RangeLine(window: window, isAtRange: false, spanStartHour: 7, spanEndHour: 11,
                             rangeHasPassed: true)
        XCTAssertEqual(line.text, "Showing 7 – 11am", "the flag only words the Range itself")
        XCTAssertTrue(line.showsReturn)
    }

    func testWrappedPassedRangeReadsTimePassed() {
        let night = WindowSpec(startHour: 22, endHour: 2)
        XCTAssertEqual(RangeLine(window: night, isAtRange: true, spanStartHour: 22, spanEndHour: 2,
                                 rangeHasPassed: true).text,
                       "Your range 10pm – 2am · Time passed")
    }
}

/// "Range has ended" (owner ruling 2026-11-04): every position of the Range
/// has passed — i.e. its LAST position has. A position before the forecast
/// start (negative, no data) is passed by definition; one with an index has
/// passed once `hasPassed(index, now)` (now ≥ its start + 1h).
final class RangeHasPassedTests: XCTestCase {
    /// Asia/Dubai, `forecastStart` 04:00Z = 8am local.
    private func deriver() throws -> TimeDeriver {
        try XCTUnwrap(TimeDeriver(forecastStart: "2026-06-19T04:00:00Z", timezone: "Asia/Dubai"))
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testAllBeforeTheForecastStartHasPassed() throws {
        // A 5–7am Range at an 8am start: positions -3..<-1, no data at all.
        // `now` is even BEFORE the forecast start — gone hours are passed anyway.
        XCTAssertTrue(try deriver().rangeHasPassed(-3..<(-1), now: date("2026-06-19T03:00:00Z")))
    }

    func testLastPositionUnderWayHasNotPassed() throws {
        // 6–10am = -2..<2; the last hour (9am, index 1) is under way at 9:30.
        XCTAssertFalse(try deriver().rangeHasPassed(-2..<2, now: date("2026-06-19T05:30:00Z")))
    }

    func testLastPositionEndedHasPassed() throws {
        // 9am ends at 10am local = 06:00Z, exactly.
        XCTAssertTrue(try deriver().rangeHasPassed(-2..<2, now: date("2026-06-19T06:00:00Z")))
    }

    func testWrappedRangeUsesItsLastPosition() throws {
        let deriver = try deriver()
        let night = try XCTUnwrap(deriver.rangePositions(window: WindowSpec(startHour: 22, endHour: 2), dayIndex: 0))
        // 10pm–2am: the last hour is 1am, which ends at 2am local = 22:00Z.
        XCTAssertFalse(deriver.rangeHasPassed(night, now: date("2026-06-19T21:30:00Z")), "1am under way")
        XCTAssertTrue(deriver.rangeHasPassed(night, now: date("2026-06-19T22:00:00Z")))
    }

    func testAFutureDayRangeHasNotPassed() throws {
        let deriver = try deriver()
        let tomorrow = try XCTUnwrap(deriver.rangePositions(window: WindowSpec(startHour: 6, endHour: 10), dayIndex: 1))
        // Late on day 0: today's Range is over, tomorrow's is not.
        XCTAssertFalse(deriver.rangeHasPassed(tomorrow, now: date("2026-06-19T19:00:00Z")))
    }

    func testAnEmptyRangeHasNotPassed() throws {
        XCTAssertFalse(try deriver().rangeHasPassed(0..<0, now: date("2026-06-20T00:00:00Z")))
    }
}
