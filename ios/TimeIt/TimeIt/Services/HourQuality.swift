import Foundation

/// Per-hour quality tier for the spec 14 gradient card. Ordered red < orange
/// < green — the same three-way verdict the server's day `rating` collapses
/// to: green ⇔ "perfect", orange ⇔ "good", red ⇔ Bad (a day of only red
/// hours is the server's `rating: null`).
enum HourTier: Int, Comparable, CaseIterable {
    case red = 0
    case orange = 1
    case green = 2

    static func < (lhs: HourTier, rhs: HourTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The on-device per-hour evaluator (spec 14 §3) — the client-side mirror of
/// the server's `evaluateHour`/`checkThreshold` (`src/decision/decision_engine.js`),
/// recorded as mirror #3 in ADR-0007. Any threshold-semantics change lands in
/// BOTH engines in the same wave; the pinning test is the §3 invariant against
/// `RealBackendResponse` (greenest run must coincide with the server window).
enum HourQuality {

    /// Any required threshold fails → .red; only optional thresholds fail →
    /// .orange; everything passes → .green (an empty profile passes).
    static func tier(for hour: HourlyWeather, thresholds: [String: Threshold]) -> HourTier {
        var allPass = true
        var allRequiredPass = true

        for (metric, threshold) in thresholds {
            if !passes(hour, metric: metric, threshold: threshold) {
                allPass = false
                if threshold.required { allRequiredPass = false }
            }
        }

        if allPass { return .green }
        if allRequiredPass { return .orange }
        return .red
    }

    /// Mirror of the server's `checkThreshold`: an absent value FAILS (absent
    /// data is never silently fine); a `forbidTrue` flag fails when raised;
    /// numeric bounds are inclusive (strict `< min` / `> max` fail).
    private static func passes(_ hour: HourlyWeather, metric: String, threshold: Threshold) -> Bool {
        if threshold.isFlag {
            guard let raised = flagValue(for: metric, in: hour) else { return false }
            return !(threshold.forbidTrue == true && raised)
        }
        guard let value = hour.numericValue(for: metric) else { return false }
        if let min = threshold.min, value < min { return false }
        if let max = threshold.max, value > max { return false }
        return true
    }

    /// The boolean wire fields a flag threshold can read. An unknown metric
    /// returns nil — and fails its threshold, like the server's undefined lookup.
    private static func flagValue(for metric: String, in hour: HourlyWeather) -> Bool? {
        switch metric {
        case "dustAlert": return hour.dustAlert
        case "seaWarning": return hour.seaWarning
        default: return nil
        }
    }
}
