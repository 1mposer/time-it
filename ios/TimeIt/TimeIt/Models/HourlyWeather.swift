import Foundation

/// One hourly forecast entry. There is no `hour` field (dropped, ADR-0004) —
/// clock times derive from `forecastStart` + `timezone` + `index`.
struct HourlyWeather: Decodable, Identifiable {
    let index: Int
    let temp: Double
    let humidity: Double
    let visibility: Double
    let uV: Double
    /// Nullable trio — the backend sends JSON `null` when the upstream
    /// provider omitted the field.
    let windSpeed: Double?
    let rainFall: Double?
    let cloudCover: Double?
    let moon: [String]
    let dustAlert: Bool
    let seaWarning: Bool
    // Coming-soon placeholders — shown on the timeline only, never thresholded.
    let darkness: Double
    let douglasScale: Double
    let swellHeight: Double
    let swellLength: Double
    let tide: Double

    var id: Int { index }

    /// The raw numeric value backing a metric key; nil for non-numeric or
    /// unknown metrics, and for the nullable trio when the provider omitted it.
    func numericValue(for metric: String) -> Double? {
        switch metric {
        case "temp": return temp
        case "humidity": return humidity
        case "visibility": return visibility
        case "uV": return uV
        case "windSpeed": return windSpeed
        case "rainFall": return rainFall
        case "cloudCover": return cloudCover
        default: return nil
        }
    }

    /// Per-metric display string. Returns "—" when the underlying value is
    /// nil so a nullable chip shows a neutral em-dash, never a misleading 0.
    func formatted(for metric: String) -> String {
        switch metric {
        case "temp": return "\(Int(temp.rounded()))°C"
        case "humidity": return "\(Int(humidity.rounded()))%"
        case "visibility": return "\(Int(visibility.rounded())) km"
        case "uV": return "UV \(Int(uV.rounded()))"
        case "windSpeed": return windSpeed.map { "\(Int($0.rounded())) km/h" } ?? "—"
        case "cloudCover": return cloudCover.map { "\(Int($0.rounded()))%" } ?? "—"
        case "rainFall": return rainFall.map { Self.millimetres($0) } ?? "—"
        case "moon": return moon.first ?? "—"
        case "dustAlert": return dustAlert ? "Dust" : "No dust"
        default: return "—"
        }
    }

    /// Human label for a metric key (used when no window start hour exists).
    static func label(for metric: String) -> String {
        switch metric {
        case "temp": return "Temperature"
        case "humidity": return "Humidity"
        case "visibility": return "Visibility"
        case "uV": return "UV Index"
        case "windSpeed": return "Wind"
        case "rainFall": return "Rain"
        case "cloudCover": return "Cloud Cover"
        case "moon": return "Moon"
        case "dustAlert": return "Dust"
        default: return metric
        }
    }

    private static func millimetres(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value)) mm"
        }
        return String(format: "%.1f mm", value)
    }
}
