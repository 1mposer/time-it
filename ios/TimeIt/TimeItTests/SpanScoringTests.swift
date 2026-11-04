import XCTest
import CoreLocation
@testable import TimeIt

/// Span scoring (owner rulings 2026-11-04): once the detail carousel has left
/// the Range, "Score 4 – 8pm" under the Showing line asks the SERVER to score
/// the shown hours — the authored Activity re-sent with `window` = the span.
/// There is no client-side score formula (the deleted ADR-0007 mirror stays
/// deleted); these tests pin the pure request/visibility/label/extraction
/// parts and the view model's one call.
@MainActor
final class SpanScoringTests: XCTestCase {

    /// Asia/Dubai is UTC+4 with no DST: 00:00Z = 4am local, so day 0 is
    /// indices 0..<20 and day 1 starts at index 20 (midnight).
    private let deriver = TimeDeriver(forecastStart: "2026-06-19T00:00:00Z", timezone: "Asia/Dubai")!

    private func slot(_ position: Int, index: Int?) -> HourSlot {
        HourSlot(position: position, localHour: (position + 4 + 24) % 24, index: index)
    }

    // MARK: Visibility

    func testButtonIsHiddenOnTheRange() {
        XCTAssertFalse(SpanScoring.showsButton(isAtRange: true,
                                               slots: [slot(2, index: 2), slot(3, index: 3)]))
    }

    func testButtonIsHiddenAwayFromTheRangeOnAnAllGoneSpan() {
        XCTAssertFalse(SpanScoring.showsButton(isAtRange: false,
                                               slots: [slot(-2, index: nil), slot(-1, index: nil)]))
        XCTAssertFalse(SpanScoring.showsButton(isAtRange: false, slots: []))
    }

    func testButtonShowsAwayFromTheRangeWithOneDataHour() {
        XCTAssertTrue(SpanScoring.showsButton(isAtRange: false,
                                              slots: [slot(-1, index: nil), slot(0, index: 0)]))
    }

    // MARK: Label

    func testLabelNamesTheSpanNotTheVerb() {
        let window = WindowSpec(startHour: 16, endHour: 20)
        XCTAssertEqual(SpanScoring.buttonLabel(window), "Score 4 – 8pm")
        XCTAssertEqual(SpanScoring.buttonAccessibilityLabel(window), "Score 4 to 8pm")
        XCTAssertEqual(SpanScoring.caption(window), "4 – 8pm")
    }

    func testWrappedSpanLabelCarriesBothMeridiems() {
        let window = WindowSpec(startHour: 22, endHour: 2)
        XCTAssertEqual(SpanScoring.buttonLabel(window), "Score 10pm – 2am")
        XCTAssertEqual(SpanScoring.buttonAccessibilityLabel(window), "Score 10pm to 2am")
    }

    func testNoonAndMidnightFollowRangeText() {
        XCTAssertEqual(SpanScoring.buttonLabel(WindowSpec(startHour: 8, endHour: 12)), "Score 8am – 12pm")
        XCTAssertEqual(SpanScoring.buttonLabel(WindowSpec(startHour: 20, endHour: 0)), "Score 8pm – 12am")
        XCTAssertEqual(SpanScoring.buttonLabel(WindowSpec(startHour: 0, endHour: 4)), "Score 12 – 4am")
    }

    func testScoreAccessibilityLabelNamesTheSpan() {
        XCTAssertEqual(SpanScoring.scoreAccessibilityLabel(verdict: "Perfect", score: 72,
                                                           span: WindowSpec(startHour: 16, endHour: 20)),
                       "Perfect, score 72 out of 100 for 4 to 8pm")
        XCTAssertEqual(SpanScoring.scoreAccessibilityLabel(verdict: "Perfect", score: 86, span: nil),
                       "Perfect, score 86 out of 100", "the day score's label is unchanged")
        XCTAssertEqual(SpanScoring.scoreAccessibilityLabel(verdict: "No Window", score: nil, span: nil),
                       "No Window, no score")
        XCTAssertEqual(SpanScoring.scoreAccessibilityLabel(verdict: "No Window", score: nil,
                                                           span: WindowSpec(startHour: 16, endHour: 20)),
                       "No Window, no score for 4 to 8pm")
    }

    // MARK: Window + request

    func testWindowIsTheSpanInLocalHoursWithAnExclusiveEnd() {
        // idx 3..<7 = 7am..11am local.
        XCTAssertEqual(SpanScoring.window(for: 3..<7, deriver: deriver), WindowSpec(startHour: 7, endHour: 11))
        // idx 18..<22 = 10pm..2am — wrapped, nocturnal on the server.
        XCTAssertEqual(SpanScoring.window(for: 18..<22, deriver: deriver), WindowSpec(startHour: 22, endHour: 2))
    }

    func testWindowGuardsTheServer400() {
        XCTAssertNil(SpanScoring.window(startHour: 5, endHour: 5), "startHour == endHour is a server 400")
        XCTAssertNil(SpanScoring.window(startHour: 24, endHour: 3), "hours outside 0..23")
        XCTAssertNil(SpanScoring.window(for: 0..<24, deriver: deriver), "a 24h span maps to equal hours")
        XCTAssertNil(SpanScoring.window(for: 3..<3, deriver: deriver), "an empty span")
        XCTAssertEqual(SpanScoring.window(startHour: 23, endHour: 0), WindowSpec(startHour: 23, endHour: 0))
    }

    func testRequestSwapsOnlyTheWindow() throws {
        let authored = Fixtures.liveSeeds[0]
        let window = WindowSpec(startHour: 7, endHour: 11)
        let request = SpanScoring.request(from: authored.activityInput, window: window)
        XCTAssertEqual(request, ActivityInput(id: authored.id,
                                              label: authored.label,
                                              displayMetrics: authored.displayMetrics,
                                              thresholds: authored.thresholds,
                                              window: window))
        // Byte-equal to the authored input except the window key.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var original = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoder.encode(authored.activityInput)) as? [String: Any])
        var swapped = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(swapped["window"] as? [String: Int], ["startHour": 7, "endHour": 11])
        original["window"] = nil
        swapped["window"] = nil
        XCTAssertEqual(NSDictionary(dictionary: original), NSDictionary(dictionary: swapped))
    }

    // MARK: Bucket index

    func testBucketIndexIsTheDayOfTheSpansFirstPosition() {
        XCTAssertEqual(SpanScoring.bucketIndex(for: 3..<7, deriver: deriver), 0, "7–11am today")
        XCTAssertEqual(SpanScoring.bucketIndex(for: 26..<30, deriver: deriver), 1, "6–10am tomorrow")
        XCTAssertEqual(SpanScoring.bucketIndex(for: -2..<2, deriver: deriver), 0,
                       "a span opening on gone hours still buckets on today")
    }

    func testWrappedSpanBucketsOnItsEvening() {
        // 10pm today .. 2am tomorrow: the server's nocturnal bucket is the
        // evening's day — day 0, not day 1.
        XCTAssertEqual(SpanScoring.bucketIndex(for: 18..<22, deriver: deriver), 0)
        XCTAssertEqual(SpanScoring.bucketIndex(for: 42..<46, deriver: deriver), 1)
    }

    func testReplyDayZeroGuard() {
        XCTAssertTrue(SpanScoring.replyDayZeroMatches(current: deriver, replyStart: "2026-06-19T00:00:00Z"))
        XCTAssertTrue(SpanScoring.replyDayZeroMatches(current: deriver, replyStart: "2026-06-19T05:00:00Z"),
                      "a later hour of the same local day keeps the day indices")
        XCTAssertFalse(SpanScoring.replyDayZeroMatches(current: deriver, replyStart: "2026-06-19T20:00:00Z"),
                       "past local midnight every dayIndex shifts by one")
        XCTAssertFalse(SpanScoring.replyDayZeroMatches(current: deriver, replyStart: "not a date"))
    }

    // MARK: Result extraction

    private func reply(days: [Day]) -> ForecastResponse {
        ForecastResponse(forecastStart: "2026-06-19T00:00:00Z",
                         timezone: "Asia/Dubai",
                         activities: [ActivityRating(activityId: "cycling", label: "Cycling",
                                                     displayMetrics: ["temp"], days: days)],
                         hours: [])
    }

    func testResultReadsTheBucketsScoreAndRating() {
        let window = WindowSpec(startHour: 7, endHour: 11)
        let response = reply(days: [Day(dayIndex: 0, rating: .perfect, startIndex: 3, endIndex: 7, duration: 4, score: 72),
                                    Day(dayIndex: 1, rating: nil, score: 14)])
        XCTAssertEqual(SpanScoring.result(from: response, bucketIndex: 0, window: window),
                       SpanScore(score: 72, rating: .perfect, window: window))
        XCTAssertEqual(SpanScoring.result(from: response, bucketIndex: 1, window: window),
                       SpanScore(score: 14, rating: nil, window: window))
    }

    func testMissingDayIsAFailedCall() {
        let window = WindowSpec(startHour: 7, endHour: 11)
        XCTAssertNil(SpanScoring.result(from: reply(days: [Day(dayIndex: 0, rating: .good, score: 50)]),
                                        bucketIndex: 3, window: window))
        XCTAssertNil(SpanScoring.result(from: reply(days: []), bucketIndex: 0, window: window))
        let empty = ForecastResponse(forecastStart: "2026-06-19T00:00:00Z", timezone: "Asia/Dubai",
                                     activities: [], hours: [])
        XCTAssertNil(SpanScoring.result(from: empty, bucketIndex: 0, window: window))
    }

    // MARK: Hero layout — the button row and the caption row

    func testTheButtonRowAddsExactlyOneRowToTheRowColumn() {
        typealias L = Theme.Detail
        XCTAssertEqual(L.rowColumnHeight(hasLine: true, hasButton: true),
                       L.rowColumnHeight(hasLine: true) + L.lineToSpanButton + L.spanButtonHeight)
        XCTAssertEqual(L.ringColumnHeight(hasCaption: true),
                       L.ringColumnHeight + L.wordToCaption + L.captionHeight)
    }

    func testThePillRowHoldsStillAsTheButtonAndCaptionComeAndGo() {
        // Owner rule: the control under the finger must not jump when the
        // button appears after a + tap, or when the score replaces it.
        typealias L = Theme.Detail
        let lineTop = L.rowColumnTop(hasLine: true)
        XCTAssertEqual(L.rowColumnTop(hasLine: true, hasButton: true), lineTop)
        XCTAssertEqual(L.rowColumnTop(hasLine: true, hasButton: false, hasCaption: true), lineTop)
        XCTAssertEqual(L.rowColumnTop(hasLine: true, hasButton: true, hasCaption: true), lineTop)
    }

    func testTheHeroGrowsToFitTheTallerColumn() {
        typealias L = Theme.Detail
        let base = L.heroHeight(hasLine: true)
        XCTAssertEqual(base, 122, "unchanged at rest")
        let withButton = L.heroHeight(hasLine: true, hasButton: true)
        XCTAssertEqual(withButton,
                       L.heroInset + L.rowColumnTop(hasLine: true)
                           + L.rowColumnHeight(hasLine: true, hasButton: true) + L.heroBottom)
        XCTAssertGreaterThan(withButton, base)
        let withCaption = L.heroHeight(hasLine: true, hasCaption: true)
        XCTAssertGreaterThanOrEqual(withCaption,
                                    L.heroInset + L.ringColumnHeight(hasCaption: true) + L.heroBottom)
        XCTAssertGreaterThan(withCaption, base)
    }

    // MARK: The view model's call

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SpanScoringTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func loadedViewModel(service: FakeRatingService) async -> DashboardViewModel {
        let vm = DashboardViewModel(api: service,
                                    locationProvider: FakeLocationProvider(location: CLLocation(latitude: 25.2, longitude: 55.27)),
                                    store: ActivityStore(defaults: defaults, seeds: Fixtures.liveSeeds),
                                    preferences: PreferencesStore(defaults: defaults))
        await vm.loadForecast()
        return vm
    }

    private var dayForecast: ForecastResponse {
        ForecastResponse(forecastStart: "2026-06-19T00:00:00Z",
                         timezone: "Asia/Dubai",
                         activities: Fixtures.liveSeeds.map {
                             ActivityRating(activityId: $0.id, label: $0.label, displayMetrics: $0.displayMetrics,
                                            days: [Day(dayIndex: 0, rating: .perfect, startIndex: 2, endIndex: 6,
                                                       duration: 4, score: 86)])
                         },
                         hours: (0..<56).map { Fixtures.makeHour(index: $0) })
    }

    func testScoreSpanSendsTheSpanWindowToTheLastFetchedCoordinate() async {
        let service = FakeRatingService(result: .success(dayForecast))
        let vm = await loadedViewModel(service: service)
        let authored = Fixtures.liveSeeds[0]
        service.result = .success(reply(days: [Day(dayIndex: 0, rating: .good, startIndex: 3, endIndex: 7,
                                                   duration: 4, score: 61)]))
        let fetchesBefore = service.fetchCount

        let result = await vm.scoreSpan(for: authored, span: 3..<7)

        XCTAssertEqual(service.fetchCount, fetchesBefore + 1, "one call")
        XCTAssertEqual(service.capturedLat, 25.2)
        XCTAssertEqual(service.capturedLon, 55.27)
        XCTAssertEqual(service.capturedActivities,
                       [SpanScoring.request(from: authored.activityInput, window: WindowSpec(startHour: 7, endHour: 11))])
        XCTAssertEqual(result, SpanScore(score: 61, rating: .good, window: WindowSpec(startHour: 7, endHour: 11)))
        // Detail-only: the dashboard's forecast is untouched.
        XCTAssertEqual(vm.forecast?.activities.count, Fixtures.liveSeeds.count)
        XCTAssertEqual(vm.forecast?.activities.first?.days.first?.score, 86)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func testScoreSpanReturnsNilOnAnAPIError() async {
        let service = FakeRatingService(result: .success(dayForecast))
        let vm = await loadedViewModel(service: service)
        service.result = .failure(APIError.providerUnavailable)

        let result = await vm.scoreSpan(for: Fixtures.liveSeeds[0], span: 3..<7)

        XCTAssertNil(result)
        XCTAssertNil(vm.errorMessage, "a failed span score never surfaces as the dashboard error")
        XCTAssertEqual(vm.forecast?.activities.first?.days.first?.score, 86)
    }

    func testScoreSpanWithoutAForecastMakesNoCall() async {
        let service = FakeRatingService(result: .success(dayForecast))
        let vm = DashboardViewModel(api: service,
                                    locationProvider: FakeLocationProvider(),
                                    store: ActivityStore(defaults: defaults, seeds: Fixtures.liveSeeds),
                                    preferences: PreferencesStore(defaults: defaults))
        let result = await vm.scoreSpan(for: Fixtures.liveSeeds[0], span: 3..<7)
        XCTAssertNil(result)
        XCTAssertEqual(service.fetchCount, 0)
    }
}
