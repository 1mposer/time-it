import Foundation

/// How a metric is edited and evaluated.
enum MetricKind: Equatable {
    /// Takes min/max bounds.
    case numeric
    /// Boolean — thresholded as `{ type: "flag", forbidTrue: true }`.
    case flag
    /// Selectable for display but not thresholdable (e.g. `moon` in #5b).
    case displayOnly
}

/// UI hint for the numeric threshold editor (slider/stepper bounds).
/// Not a validation rule — the backend accepts any finite number.
struct MetricRange: Equatable {
    let min: Double
    let max: Double
    let step: Double
}

/// One selectable metric, provider-agnostic: both the static catalog and a
/// future RemoteMetricCatalog produce this same shape.
struct MetricDescriptor: Identifiable, Equatable {
    /// The wire key — must match the backend metric catalog exactly (case-sensitive).
    let key: String
    let displayName: String
    /// Unit label for the threshold editor ("°C", "km/h", "%", "mm"; empty when unitless).
    let unit: String
    /// Chip icon from the SF Symbols manifest (design-decisions §B).
    let iconSymbol: String
    let kind: MetricKind
    /// Reserved for tier gating — all false today (Pro deferred, #5b §8).
    let pro: Bool
    let range: MetricRange?

    var id: String { key }
    var isThresholdable: Bool { kind != .displayOnly }
}

/// The swap seam (#5b §4, hard requirement): views and validation depend on
/// this protocol, never on a global constant, so the static catalog can be
/// replaced by a network-backed conformer with zero call-site changes.
protocol MetricCatalogProviding {
    var metrics: [MetricDescriptor] { get }
}

extension MetricCatalogProviding {
    func descriptor(for key: String) -> MetricDescriptor? {
        metrics.first { $0.key == key }
    }

    var liveKeys: Set<String> {
        Set(metrics.map(\.key))
    }
}

/// Static client-side catalog of the LIVE metrics.
///
/// Hand-maintained mirror of `LIVE_METRICS` in `src/weather/metricCatalog.js` —
/// it must stay in sync until the server route lands (MetricCatalogTests pins
/// the set). Never add a coming-soon metric (`darkness`, `douglasScale`,
/// `swellHeight`, `swellLength`, `tide`, `seaWarning`): the backend hard-400s
/// it, and validation is atomic, so one bad metric blanks the whole dashboard.
///
/// TODO: RemoteMetricCatalog via GET /api/v1/metrics (pending ADR-0006, unwritten).
struct StaticMetricCatalog: MetricCatalogProviding {
    var metrics: [MetricDescriptor] { Self.all }

    // Built once — the struct is instantiated freely (default args, per-chip
    // lookups), so the descriptor list must not be rebuilt per instance.
    private static let all: [MetricDescriptor] = [
        MetricDescriptor(key: "temp", displayName: "Temperature", unit: "°C",
                         iconSymbol: "thermometer.medium", kind: .numeric, pro: false,
                         range: MetricRange(min: -10, max: 50, step: 1)),
        MetricDescriptor(key: "humidity", displayName: "Humidity", unit: "%",
                         iconSymbol: "humidity.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 100, step: 5)),
        MetricDescriptor(key: "windSpeed", displayName: "Wind Speed", unit: "km/h",
                         iconSymbol: "wind", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 80, step: 1)),
        MetricDescriptor(key: "rainFall", displayName: "Rainfall", unit: "mm",
                         iconSymbol: "cloud.rain.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 20, step: 0.5)),
        MetricDescriptor(key: "cloudCover", displayName: "Cloud Cover", unit: "%",
                         iconSymbol: "cloud.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 100, step: 5)),
        MetricDescriptor(key: "visibility", displayName: "Visibility", unit: "km",
                         iconSymbol: "eye.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 20, step: 1)),
        MetricDescriptor(key: "uV", displayName: "UV Index", unit: "",
                         iconSymbol: "sun.max.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 12, step: 1)),
        MetricDescriptor(key: "moon", displayName: "Moon Phase", unit: "",
                         iconSymbol: "moon.stars.fill", kind: .displayOnly, pro: false,
                         range: nil),
        MetricDescriptor(key: "dustAlert", displayName: "Dust Alert", unit: "",
                         iconSymbol: "sun.dust.fill", kind: .flag, pro: false,
                         range: nil),
    ]
}
