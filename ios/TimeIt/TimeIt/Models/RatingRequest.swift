import Foundation

/// Body of `POST /api/v1/rating` (ADR-0005). `lat`/`lon` travel in the body,
/// not the query string, and there is no `timezone` field — the location's
/// zone is resolved server-side.
struct RatingRequest: Encodable {
    let lat: Double
    let lon: Double
    let activities: [ActivityInput]
}

/// One caller-authored activity (the engine holds no list — ADR-0002).
/// `window` is a #5b authoring concern; #5a's seeds are diurnal, so the key
/// is omitted entirely rather than sent as null.
struct ActivityInput: Encodable {
    /// Client-stable, unique within the request; echoed back as `activityId`.
    let id: String
    let label: String
    /// Ordered render superset; `thresholds.keys ⊆ displayMetrics`.
    let displayMetrics: [String]
    let thresholds: [String: Threshold]
}

/// A numeric constraint `{ min?, max?, required }` (≥1 bound) or a flag
/// `{ type: "flag", forbidTrue: true, required }`. Synthesized encoding
/// omits nil optionals, matching the ADR-0005 shape.
struct Threshold: Encodable {
    var min: Double?
    var max: Double?
    var required: Bool
    var type: String?
    var forbidTrue: Bool?

    init(min: Double? = nil, max: Double? = nil, required: Bool, type: String? = nil, forbidTrue: Bool? = nil) {
        self.min = min
        self.max = max
        self.required = required
        self.type = type
        self.forbidTrue = forbidTrue
    }
}
