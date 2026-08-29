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

/// Wire verdict of a day bucket: `"perfect" | "good" | null`. Tolerant-decoder
/// posture (2026-07-12 hardening): an unrecognized verdict string decodes to
/// `.unknown` — the decode never fails, and an unknown verdict renders like a
/// null day (no qualifying Window; never favorable on a verdict this build
/// doesn't understand).
enum Rating: Equatable {
    case perfect
    case good
    case unknown(String)

    init(wire: String) {
        switch wire {
        case "perfect": self = .perfect
        case "good": self = .good
        default: self = .unknown(wire)
        }
    }

    /// The verdicts this build understands as a qualifying Window.
    var isQualifying: Bool { self == .perfect || self == .good }
}

/// One day-bucket's best Window. `startIndex`/`endIndex` are GLOBAL indices
/// into `hours[]` (half-open, `endIndex` exclusive); the keys are absent from
/// the JSON when `rating` is null.
struct Day: Identifiable {
    let dayIndex: Int
    let rating: Rating?
    let startIndex: Int?
    let endIndex: Int?
    let duration: Int?

    var id: Int { dayIndex }

    /// A qualifying Window exists. `nil` and `.unknown` both render the
    /// no-window state — check this, never `rating != nil`.
    var hasWindow: Bool { rating?.isQualifying == true }

    var ratingDisplay: String {
        switch rating {
        case .perfect: return "Perfect"
        case .good: return "Good"
        default: return "No Window"
        }
    }
}

/// Decoder in an extension so the synthesized memberwise initializer stays
/// available for tests/fixtures (the HourlyWeather pattern).
extension Day: Decodable {
    private enum CodingKeys: String, CodingKey {
        case dayIndex, rating, startIndex, endIndex, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayIndex = try container.decode(Int.self, forKey: .dayIndex)
        rating = (try container.decodeIfPresent(String.self, forKey: .rating)).map(Rating.init(wire:))
        startIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex)
        endIndex = try container.decodeIfPresent(Int.self, forKey: .endIndex)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
    }
}
