import Foundation

/// Chip colour tiers — the per-metric judgment table behind the metric chips
/// (card + detail). Boundaries are the product decision pinned in
/// ios/guidelines/Guidelines.md (MetricColorTests). Colors live in `Theme`
/// (`chipTextColor`/`chipBackgroundColor`) — this table stays pure.
enum MetricTier: Equatable {
    case green
    case orange
    case red
    /// No data (nil value) or a metric with no tier table.
    case neutral

    static func tier(for metric: String, value: Double?) -> MetricTier {
        guard let value else { return .neutral }
        switch metric {
        case "temp":
            if value >= 38 { return .red }
            if value >= 33 { return .orange }
            return .green
        case "uV":
            if value >= 7 { return .red }
            if value >= 4 { return .orange }
            return .green
        case "windSpeed":
            if value >= 36 { return .red }
            if value >= 21 { return .orange }
            return .green
        case "humidity":
            if value >= 76 { return .red }
            if value >= 61 { return .orange }
            return .green
        case "cloudCover":
            if value >= 61 { return .red }
            if value >= 21 { return .orange }
            return .green
        default:
            return .neutral
        }
    }
}
