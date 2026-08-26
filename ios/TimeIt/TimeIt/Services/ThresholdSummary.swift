import Foundation

/// States the Activity's setup once — thresholds don't vary by hour, so this
/// replaces 24 repeats. Short metric names; unit glued for symbols, spaced
/// for words; "≤"/"≥" for one-sided bounds; " required"/" optional" suffix;
/// joined " · " in displayMetrics order.
enum ThresholdSummary {

    /// nil when nothing is thresholded — an all-display profile has nothing
    /// to state, so the block hides.
    static func line(for activity: AuthoredActivity,
                     catalog: MetricCatalogProviding = StaticMetricCatalog()) -> String? {
        let entries = activity.displayMetrics.compactMap { metric -> String? in
            guard let threshold = activity.thresholds[metric] else { return nil }
            return entry(metric: metric, threshold: threshold, catalog: catalog)
        }
        return entries.isEmpty ? nil : entries.joined(separator: " · ")
    }

    private static func entry(metric: String, threshold: Threshold,
                              catalog: MetricCatalogProviding) -> String {
        let name = catalog.shortName(for: metric)
        let suffix = threshold.required ? "required" : "optional"
        if threshold.isFlag {
            // forbidTrue is the only flag shape — requireTrue doesn't exist yet (Issue #8).
            return "No \(name.lowercased()) alerts \(suffix)"
        }
        let unit = catalog.descriptor(for: metric)?.unit ?? ""
        switch (threshold.min, threshold.max) {
        case let (min?, max?):
            return "\(name) \(number(min)) – \(withUnit(max, unit)) \(suffix)"
        case let (min?, nil):
            return "\(name) ≥ \(withUnit(min, unit)) \(suffix)"
        case let (nil, max?):
            return "\(name) ≤ \(withUnit(max, unit)) \(suffix)"
        case (nil, nil):
            // Bound-less numerics can't be saved (validation) — belt and braces.
            return "\(name) \(suffix)"
        }
    }

    /// "32°C" / "20%" glue symbol units; "25 km/h" / "0.2 mm" space word
    /// units — matching `HourlyWeather.formatted(for:)`'s chip dialect.
    private static func withUnit(_ value: Double, _ unit: String) -> String {
        guard !unit.isEmpty else { return number(value) }
        let gluedUnits: Set<String> = ["°C", "%"]
        return gluedUnits.contains(unit) ? "\(number(value))\(unit)" : "\(number(value)) \(unit)"
    }

    private static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
