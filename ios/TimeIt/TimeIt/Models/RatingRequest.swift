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
/// `window` is optional: synthesized encoding omits the key entirely when nil
/// (whole-day), rather than sending null. Equatable so snapshot bodies
/// (DeviceSnapshotBody) compare whole in tests.
struct ActivityInput: Encodable, Equatable {
    /// Client-stable, unique within the request; echoed back as `activityId`.
    let id: String
    let label: String
    /// Ordered render superset; `thresholds.keys ⊆ displayMetrics`.
    let displayMetrics: [String]
    let thresholds: [String: Threshold]
    /// Optional time-of-day window; wrap (startHour > endHour) = nocturnal.
    let window: WindowSpec?

    init(id: String,
         label: String,
         displayMetrics: [String],
         thresholds: [String: Threshold],
         window: WindowSpec? = nil) {
        self.id = id
        self.label = label
        self.displayMetrics = displayMetrics
        self.thresholds = thresholds
        self.window = window
    }
}

/// A time-of-day window `{ startHour, endHour }` — integers 0..23 in the
/// FORECAST LOCATION's local hours, half-open [startHour, endHour).
/// `startHour > endHour` wraps midnight (nocturnal → night-stitch);
/// `startHour == endHour` is rejected server-side (ADR-0005 §5).
struct WindowSpec: Codable, Equatable, Hashable {
    var startHour: Int
    var endHour: Int

    /// The only nocturnal signal — a wrapped window.
    var isWrapped: Bool { startHour > endHour }
}

/// A numeric constraint `{ min?, max?, required }` (≥1 bound) or a flag
/// `{ type: "flag", forbidTrue: true, required }`. Synthesized encoding
/// omits nil optionals, matching the ADR-0005 shape. Codable so authored
/// activities persist locally (#5b §3).
struct Threshold: Codable, Equatable, Hashable {
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

    /// True for the `{ type: "flag", forbidTrue: true }` shape.
    var isFlag: Bool { type == "flag" }
}
