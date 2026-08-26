import Foundation

/// One hourly forecast entry. There is no `hour` field (dropped, ADR-0004) —
/// clock times derive from `forecastStart` + `timezone` + `index`. Decoding is deliberately
/// null-tolerant: every metric is optional and defaults safely, so one
/// unexpected provider `null` renders "—" instead of blanking the dashboard.
struct HourlyWeather: Decodable, Identifiable {
    let index: Int
    /// nil = the provider had no value; renders "—", never a 0.
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

    // Deliberately no metric-name table here — human names come from the
    // metric catalog only; a second table here drifted once already.

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

    /// Tolerant decode: a missing key or JSON null becomes nil (or a safe
    /// default); only `index` is required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        temp = try c.decodeIfPresent(Double.self, forKey: .temp)
        humidity = try c.decodeIfPresent(Double.self, forKey: .humidity)
        visibility = try c.decodeIfPresent(Double.self, forKey: .visibility)
        uV = try c.decodeIfPresent(Double.self, forKey: .uV)
        windSpeed = try c.decodeIfPresent(Double.self, forKey: .windSpeed)
        rainFall = try c.decodeIfPresent(Double.self, forKey: .rainFall)
        cloudCover = try c.decodeIfPresent(Double.self, forKey: .cloudCover)
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
