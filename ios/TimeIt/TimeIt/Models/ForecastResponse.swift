import Foundation

/// Top-level response of `POST /api/v1/rating`.
/// Wire contract: CLAUDE.md "API response contract" (ADR-0004).
struct ForecastResponse: Decodable {
    /// ISO 8601 UTC with a `Z` suffix — the instant of `hours[0]`.
    let forecastStart: String
    /// The forecast location's IANA zone. All clock times and day labels
    /// render in this zone, never the device zone.
    let timezone: String
    /// One entry per requested activity, echoed in request order.
    let activities: [ActivityRating]
    /// Provider-determined length, up to 168 — always read `hours.count`.
    let hours: [HourlyWeather]
}

/// One activity's evaluation result. `days.count` is per-activity
/// (7/8 diurnal, one shorter nocturnal) — never hardcode 7.
struct ActivityRating: Decodable, Identifiable {
    let activityId: String
    let label: String
    let displayMetrics: [String]
    let days: [Day]

    var id: String { activityId }
}

/// One day-bucket's best Window. `startIndex`/`endIndex` are GLOBAL indices
/// into `hours[]` (half-open, `endIndex` exclusive); the keys are absent from
/// the JSON when `rating` is null.
struct Day: Decodable, Identifiable {
    let dayIndex: Int
    let rating: String?
    let startIndex: Int?
    let endIndex: Int?
    let duration: Int?

    var id: Int { dayIndex }

    var hasWindow: Bool { rating != nil }

    var ratingDisplay: String {
        switch rating {
        case "perfect": return "Perfect"
        case "good": return "Good"
        default: return "No Window"
        }
    }
}
