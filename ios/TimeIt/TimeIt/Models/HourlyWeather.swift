import Foundation

/// One hourly forecast entry. There is no `hour` field (dropped, ADR-0004) —
/// clock times derive from `forecastStart` + `timezone` + `index`.
///
/// Decoding is deliberately null-tolerant (see the custom `init(from:)` below):
/// every metric is optional and every non-structural field has a safe default,
/// so a single unexpected `null` from the upstream provider (e.g. Meteosource
/// returns `uv_index: null` at night) renders as "—" for that one value rather
/// than throwing and blanking the entire dashboard. Only `index` (the array
/// position) is required.
struct HourlyWeather: Decodable, Identifiable {
    let index: Int
    /// Metrics are all optional: the backend sends JSON `null` (or omits the key)
    /// whenever the upstream provider had no value. A nil renders "—", never a 0.
    let temp: Double?
    let humidity: Double?
    let visibility: Double?
    let uV: Double?
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
    /// unknown metrics, and for any metric the provider omitted.
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
    /// nil so a chip shows a neutral em-dash, never a misleading 0.
    func formatted(for metric: String) -> String {
        switch metric {
        case "temp": return temp.map { "\(Int($0.rounded()))°C" } ?? "—"
        case "humidity": return humidity.map { "\(Int($0.rounded()))%" } ?? "—"
        case "visibility": return visibility.map { "\(Int($0.rounded())) km" } ?? "—"
        case "uV": return uV.map { "UV \(Int($0.rounded()))" } ?? "—"
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

// The custom decoder lives in an extension so the synthesized memberwise
// initializer stays available for tests/fixtures.
extension HourlyWeather {
    enum CodingKeys: String, CodingKey {
        case index, temp, humidity, visibility, uV, windSpeed, rainFall, cloudCover
        case moon, dustAlert, seaWarning, darkness, douglasScale, swellHeight, swellLength, tide
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `index` is structural (the position in hours[]) — required.
        index = try c.decode(Int.self, forKey: .index)
        // Every metric is decoded tolerantly: a missing key OR an explicit JSON
        // null becomes nil (→ "—"), never a decode failure that blanks the app.
        temp = try c.decodeIfPresent(Double.self, forKey: .temp)
        humidity = try c.decodeIfPresent(Double.self, forKey: .humidity)
        visibility = try c.decodeIfPresent(Double.self, forKey: .visibility)
        uV = try c.decodeIfPresent(Double.self, forKey: .uV)
        windSpeed = try c.decodeIfPresent(Double.self, forKey: .windSpeed)
        rainFall = try c.decodeIfPresent(Double.self, forKey: .rainFall)
        cloudCover = try c.decodeIfPresent(Double.self, forKey: .cloudCover)
        // Non-metric fields default rather than fail, for the same reason.
        moon = try c.decodeIfPresent([String].self, forKey: .moon) ?? []
        dustAlert = try c.decodeIfPresent(Bool.self, forKey: .dustAlert) ?? false
        seaWarning = try c.decodeIfPresent(Bool.self, forKey: .seaWarning) ?? false
        darkness = try c.decodeIfPresent(Double.self, forKey: .darkness) ?? 0
        douglasScale = try c.decodeIfPresent(Double.self, forKey: .douglasScale) ?? 0
        swellHeight = try c.decodeIfPresent(Double.self, forKey: .swellHeight) ?? 0
        swellLength = try c.decodeIfPresent(Double.self, forKey: .swellLength) ?? 0
        tide = try c.decodeIfPresent(Double.self, forKey: .tide) ?? 0
    }
}
