import XCTest
@testable import TimeIt

/// Lane CACHE (owner rules 2026-11-11): the last ForecastResponse persists on
/// disk keyed by 2-dp lat/lon, fresh for 3 h from the fetch instant.
final class ForecastCacheTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForecastCacheTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var fileURL: URL { directory.appendingPathComponent("forecast.json") }

    private let fetchedAt = ISO8601DateFormatter().date(from: "2026-06-19T12:10:00Z")!

    /// A wire response with every tolerant edge: a null day (keys absent), an
    /// unknown verdict, a nil score, nil metrics (hour 1/2).
    private func wireResponse() throws -> ForecastResponse {
        let json = Fixtures.forecastResponseJSON(hourCount: 3)
            .replacingOccurrences(of: #""rating": "good""#, with: #""rating": "superb""#)
        return try JSONDecoder().decode(ForecastResponse.self, from: Data(json.utf8))
    }

    func testKeyRoundsCoordinatesToTwoDecimals() {
        XCTAssertEqual(ForecastCache.key(lat: 25.20481, lon: 55.27079), "25.20,55.27")
        XCTAssertEqual(ForecastCache.key(lat: 25.2049, lon: 55.2701), ForecastCache.key(lat: 25.2001, lon: 55.2749))
        XCTAssertNotEqual(ForecastCache.key(lat: 25.20, lon: 55.27), ForecastCache.key(lat: 25.22, lon: 55.27))
    }

    func testEntryPersistsAcrossInstancesWithTheWireShapeIntact() throws {
        let entry = ForecastCacheEntry(key: "25.20,55.27", fetchedAt: fetchedAt,
                                       response: try wireResponse(),
                                       fingerprints: ["cycling": "a", "fishing-lite": "b"])
        ForecastCache(fileURL: fileURL).store(entry)

        let reloaded = try XCTUnwrap(ForecastCache(fileURL: fileURL).entry(for: "25.20,55.27"))
        XCTAssertEqual(reloaded.fetchedAt, fetchedAt)
        XCTAssertEqual(reloaded.fingerprints, ["cycling": "a", "fishing-lite": "b"])
        XCTAssertEqual(reloaded.response.forecastStart, "2026-06-19T12:00:00Z")
        XCTAssertEqual(reloaded.response.timezone, "Asia/Dubai")
        XCTAssertEqual(reloaded.response.activities.map(\.activityId), ["cycling", "fishing-lite"])
        let days = reloaded.response.activities[0].days
        XCTAssertEqual(days[0].rating, .perfect)
        XCTAssertEqual(days[0].startIndex, 3)
        XCTAssertEqual(days[0].endIndex, 9)
        XCTAssertEqual(days[0].duration, 6)
        XCTAssertNil(days[1].rating)
        XCTAssertNil(days[1].startIndex, "a null day keeps its window keys absent")
        XCTAssertNil(days[1].score)
        XCTAssertEqual(days[2].rating, .unknown("superb"), "an unknown verdict round-trips as itself")
        let hours = reloaded.response.hours
        XCTAssertEqual(hours.count, 3)
        XCTAssertNil(hours[1].windSpeed)
        XCTAssertNil(hours[1].cloudCover)
        XCTAssertNil(hours[2].uV)
        XCTAssertEqual(hours[0].temp, 24)
        XCTAssertEqual(hours[0].moon, ["waxing crescent"])
    }

    func testScoreRoundTrips() throws {
        let response = Fixtures.makeForecast(activities: [
            ActivityRating(activityId: "a", label: "A", displayMetrics: ["temp"],
                           days: [Day(dayIndex: 0, rating: .good, startIndex: 1, endIndex: 3, duration: 2, score: 67)])
        ])
        let cache = ForecastCache(fileURL: fileURL)
        cache.store(ForecastCacheEntry(key: "k", fetchedAt: fetchedAt, response: response, fingerprints: [:]))
        let day = try XCTUnwrap(ForecastCache(fileURL: fileURL).entry(for: "k")?.response.activities.first?.days.first)
        XCTAssertEqual(day.score, 67)
        XCTAssertEqual(day.rating, .good)
    }

    func testAnotherKeyMisses() throws {
        let cache = ForecastCache(fileURL: fileURL)
        cache.store(ForecastCacheEntry(key: "25.20,55.27", fetchedAt: fetchedAt,
                                       response: try wireResponse(), fingerprints: [:]))
        XCTAssertNil(cache.entry(for: "24.45,54.38"))
        XCTAssertNotNil(cache.entry(for: "25.20,55.27"))
    }

    func testMemoryOnlyCacheHoldsWithinTheInstanceAndWritesNothing() throws {
        let cache = ForecastCache(fileURL: nil)
        cache.store(ForecastCacheEntry(key: "k", fetchedAt: fetchedAt, response: try wireResponse(), fingerprints: [:]))
        XCTAssertNotNil(cache.entry(for: "k"))
        XCTAssertNil(ForecastCache(fileURL: nil).entry(for: "k"))
    }

    func testFreshForThreeHoursFromTheFetchInstant() throws {
        let entry = ForecastCacheEntry(key: "k", fetchedAt: fetchedAt, response: try wireResponse(), fingerprints: [:])
        XCTAssertTrue(entry.isFresh(now: fetchedAt))
        XCTAssertTrue(entry.isFresh(now: fetchedAt.addingTimeInterval(3 * 3600 - 1)))
        XCTAssertFalse(entry.isFresh(now: fetchedAt.addingTimeInterval(3 * 3600)), "3 h is the TTL (owner, 2026-11-11)")
        XCTAssertFalse(entry.isFresh(now: fetchedAt.addingTimeInterval(-60)),
                       "a clock set back behind the fetch can't vouch for the data")
    }

    func testClearRemovesTheEntryFromDisk() throws {
        let cache = ForecastCache(fileURL: fileURL)
        cache.store(ForecastCacheEntry(key: "k", fetchedAt: fetchedAt, response: try wireResponse(), fingerprints: [:]))
        cache.clear()
        XCTAssertNil(cache.entry(for: "k"))
        XCTAssertNil(ForecastCache(fileURL: fileURL).entry(for: "k"))
    }
}
