import Foundation

/// The last `/rating` response, as the dashboard last drew it (lane CACHE,
/// owner rules 2026-11-11). Keyed by the location at 2 dp — the server's own
/// weather-cache key (~1.1 km) — and anchored on the instant it was fetched.
/// `fingerprints` maps each rated Activity id to the wire input it was rated
/// with, so the view-model can tell which Activities changed since.
struct ForecastCacheEntry: Codable {
    let key: String
    /// Device-clock instant of the full fetch. A merged single-Activity POST
    /// never moves it — the "Updated" label and the TTL keep reading the
    /// oldest data in the response.
    let fetchedAt: Date
    let response: ForecastResponse
    let fingerprints: [String: String]

    /// 3 h (owner, 2026-11-11). The server memoises the provider for 60 min,
    /// so a client refetch sooner than that buys nothing.
    static let ttl: TimeInterval = 3 * 3600

    /// This entry replayed in `order` (ids absent from it are dropped), with
    /// `merging`'s ratings replacing or adding their ids. `fetchedAt` and
    /// `hours` are kept — a merge never re-ages the response. Callers merge
    /// only a reply sharing this entry's `forecastStart` + `timezone`.
    func reconciled(order: [String], merging replies: [ActivityRating],
                    fingerprints: [String: String]) -> ForecastCacheEntry {
        let replyById = Dictionary(replies.map { ($0.activityId, $0) }, uniquingKeysWith: { first, _ in first })
        let cachedById = Dictionary(response.activities.map { ($0.activityId, $0) },
                                    uniquingKeysWith: { first, _ in first })
        let activities = order.compactMap { replyById[$0] ?? cachedById[$0] }
        let kept = Set(activities.map(\.activityId))
        return ForecastCacheEntry(key: key,
                                  fetchedAt: fetchedAt,
                                  response: ForecastResponse(forecastStart: response.forecastStart,
                                                             timezone: response.timezone,
                                                             activities: activities,
                                                             hours: response.hours),
                                  fingerprints: fingerprints.filter { kept.contains($0.key) })
    }

    /// Fresh while `now` is within the TTL of the fetch. A device clock set
    /// back before the fetch reads stale — the age can't be trusted.
    func isFresh(now: Date) -> Bool {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age < Self.ttl
    }
}

/// One-entry store for `ForecastCacheEntry`: a JSON file in Caches (the OS
/// may purge it — a miss just means a refetch), or memory only when
/// `fileURL` is nil. Rating logic never lives here — the cache only replays
/// what the server said (ADR-0002/0007).
final class ForecastCache {
    private let fileURL: URL?
    private var current: ForecastCacheEntry?
    private var loaded = false

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// The production cache: `Caches/forecast-cache.json`. Memory-only (and
    /// so fresh per process) in a UI-test mock run and under XCTest — their
    /// state must never leak between launches or tests, and the app's
    /// UITEST_RESET does not know about this file.
    static func standard() -> ForecastCache {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun || NSClassFromString("XCTestCase") != nil {
            return ForecastCache(fileURL: nil)
        }
        #endif
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return ForecastCache(fileURL: caches?.appendingPathComponent("forecast-cache.json"))
    }

    /// The 2-dp location key.
    static func key(lat: Double, lon: Double) -> String {
        String(format: "%.2f,%.2f", locale: Locale(identifier: "en_US_POSIX"), lat, lon)
    }

    /// The stable fingerprint of an Activity's wire input (sorted keys — the
    /// thresholds dictionary would otherwise encode in any order).
    static func fingerprint(_ input: ActivityInput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(input)).map { String(decoding: $0, as: UTF8.self) } ?? UUID().uuidString
    }

    /// The stored entry when it belongs to `key`, at any age.
    func entry(for key: String) -> ForecastCacheEntry? {
        loadIfNeeded()
        guard let current, current.key == key else { return nil }
        return current
    }

    func store(_ entry: ForecastCacheEntry) {
        loaded = true
        current = entry
        guard let fileURL else { return }
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func clear() {
        loaded = true
        current = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        current = try? JSONDecoder().decode(ForecastCacheEntry.self, from: data)
    }
}

// MARK: - Encodable back to the wire shape
//
// The response models are Decodable-only (they live in Models/); the cache
// re-encodes them in the exact wire shape so the models' own tolerant
// decoders read the file back. Absent-when-nil keys stay absent.

extension ForecastResponse: Encodable {
    private enum CacheKeys: String, CodingKey { case forecastStart, timezone, activities, hours }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CacheKeys.self)
        try c.encode(forecastStart, forKey: .forecastStart)
        try c.encode(timezone, forKey: .timezone)
        try c.encode(activities, forKey: .activities)
        try c.encode(hours, forKey: .hours)
    }
}

extension ActivityRating: Encodable {
    private enum CacheKeys: String, CodingKey { case activityId, label, displayMetrics, days }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CacheKeys.self)
        try c.encode(activityId, forKey: .activityId)
        try c.encode(label, forKey: .label)
        try c.encode(displayMetrics, forKey: .displayMetrics)
        try c.encode(days, forKey: .days)
    }
}

extension Day: Encodable {
    private enum CacheKeys: String, CodingKey { case dayIndex, rating, startIndex, endIndex, duration, score }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CacheKeys.self)
        try c.encode(dayIndex, forKey: .dayIndex)
        switch rating {
        case .perfect: try c.encode("perfect", forKey: .rating)
        case .good: try c.encode("good", forKey: .rating)
        case .unknown(let wire): try c.encode(wire, forKey: .rating)
        case nil: try c.encodeNil(forKey: .rating)
        }
        try c.encodeIfPresent(startIndex, forKey: .startIndex)
        try c.encodeIfPresent(endIndex, forKey: .endIndex)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encodeIfPresent(score, forKey: .score)
    }
}

extension HourlyWeather: Encodable {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(index, forKey: .index)
        try c.encodeIfPresent(temp, forKey: .temp)
        try c.encodeIfPresent(humidity, forKey: .humidity)
        try c.encodeIfPresent(visibility, forKey: .visibility)
        try c.encodeIfPresent(uV, forKey: .uV)
        try c.encodeIfPresent(windSpeed, forKey: .windSpeed)
        try c.encodeIfPresent(rainFall, forKey: .rainFall)
        try c.encodeIfPresent(cloudCover, forKey: .cloudCover)
        try c.encode(moon, forKey: .moon)
        try c.encode(dustAlert, forKey: .dustAlert)
        try c.encode(seaWarning, forKey: .seaWarning)
        try c.encode(darkness, forKey: .darkness)
        try c.encode(douglasScale, forKey: .douglasScale)
        try c.encode(swellHeight, forKey: .swellHeight)
        try c.encode(swellLength, forKey: .swellLength)
        try c.encode(tide, forKey: .tide)
    }
}
