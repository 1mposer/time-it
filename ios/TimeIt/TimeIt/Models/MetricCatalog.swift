import Foundation

/// How a metric is edited and evaluated.
enum MetricKind: Equatable {
    /// Takes min/max bounds.
    case numeric
    /// Boolean — thresholded as `{ type: "flag", forbidTrue: true }`.
    case flag
    /// Selectable for display but not thresholdable (e.g. `moon`).
    case displayOnly
}

/// UI hint for the numeric threshold editor (slider/stepper bounds).
/// Not a validation rule — the backend accepts any finite number.
struct MetricRange: Equatable {
    let min: Double
    let max: Double
    let step: Double
}

/// Which thumbs the threshold slider shows: dual-thumb vs single-thumb.
enum BoundStyle { case range, maxOnly, minOnly }

/// Which end(s) of the slider track read as danger (red).
enum GradientSemantic { case dangerHigh, dangerLow, dangerBothEnds }

/// One selectable metric, provider-agnostic: both the static catalog and a
/// future RemoteMetricCatalog produce this same shape.
struct MetricDescriptor: Identifiable, Equatable {
    /// The wire key — must match the backend metric catalog exactly (case-sensitive).
    let key: String
    let displayName: String
    /// Unit label for the threshold editor ("°C", "km/h", "%", "mm"; empty when unitless).
    let unit: String
    /// Chip icon from the SF Symbols manifest.
    let iconSymbol: String
    let kind: MetricKind
    /// Reserved for tier gating — all false today.
    let pro: Bool
    let range: MetricRange?
    /// Compact name for dense surfaces ("Temp", "Wind"); nil falls back to
    /// `displayName`. Defaulted so existing memberwise call sites stay valid.
    var shortName: String? = nil
    /// Threshold-slider table (numeric metrics only) — all defaulted so other
    /// call sites don't change. `presetMin`/`presetMax` are the one-tap
    /// threshold prefill; nil = that bound isn't preset.
    var boundStyle: BoundStyle? = nil
    var gradient: GradientSemantic? = nil
    var presetMin: Double? = nil
    var presetMax: Double? = nil

    var id: String { key }
    var isThresholdable: Bool { kind != .displayOnly }
}

/// The swap seam: views and validation depend on this protocol, never on a
/// global constant, so a network-backed catalog can replace the static one
/// with zero call-site changes.
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

    /// Human name for a wire key; the key itself when unknown. The ONLY metric
    /// name table — a view keeping its own copy would silently drift.
    func displayName(for key: String) -> String {
        descriptor(for: key)?.displayName ?? key
    }

    /// Chip icon for a wire key; the guardrail glyph when unknown.
    func iconSymbol(for key: String) -> String {
        descriptor(for: key)?.iconSymbol ?? "questionmark.circle"
    }

    /// Compact name for a wire key; falls back to the display name, then the key.
    func shortName(for key: String) -> String {
        guard let descriptor = descriptor(for: key) else { return key }
        return descriptor.shortName ?? descriptor.displayName
    }
}

/// Static client-side catalog of the LIVE metrics — a hand-maintained mirror
/// of `LIVE_METRICS` in `src/weather/metricCatalog.js`; the two must stay in
/// sync. Never add a coming-soon metric: the backend hard-400s it, and one
/// bad metric blanks the whole dashboard.
/// TODO: replace with a RemoteMetricCatalog via GET /api/v1/metrics.
struct StaticMetricCatalog: MetricCatalogProviding {
    var metrics: [MetricDescriptor] { Self.all }

    // Built once — the struct is instantiated freely, so the descriptor list
    // must not be rebuilt per instance.
    private static let all: [MetricDescriptor] = [
        MetricDescriptor(key: "temp", displayName: "Temperature", unit: "°C",
                         iconSymbol: "thermometer.medium", kind: .numeric, pro: false,
                         range: MetricRange(min: -10, max: 50, step: 1), shortName: "Temp",
                         boundStyle: .range, gradient: .dangerBothEnds, presetMin: 15, presetMax: 32),
        MetricDescriptor(key: "humidity", displayName: "Humidity", unit: "%",
                         iconSymbol: "humidity.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 100, step: 5),
                         boundStyle: .maxOnly, gradient: .dangerHigh, presetMax: 70),
        MetricDescriptor(key: "windSpeed", displayName: "Wind Speed", unit: "km/h",
                         iconSymbol: "wind", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 80, step: 1), shortName: "Wind",
                         boundStyle: .maxOnly, gradient: .dangerHigh, presetMax: 25),
        MetricDescriptor(key: "rainFall", displayName: "Rainfall", unit: "mm",
                         iconSymbol: "cloud.rain.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 20, step: 0.5), shortName: "Rain",
                         boundStyle: .maxOnly, gradient: .dangerHigh, presetMax: 0.2),
        MetricDescriptor(key: "cloudCover", displayName: "Cloud Cover", unit: "%",
                         iconSymbol: "cloud.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 100, step: 5), shortName: "Cloud",
                         boundStyle: .maxOnly, gradient: .dangerHigh, presetMax: 40),
        MetricDescriptor(key: "visibility", displayName: "Visibility", unit: "km",
                         iconSymbol: "eye.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 20, step: 1),
                         boundStyle: .minOnly, gradient: .dangerLow, presetMin: 8),
        MetricDescriptor(key: "uV", displayName: "UV Index", unit: "",
                         iconSymbol: "sun.max.fill", kind: .numeric, pro: false,
                         range: MetricRange(min: 0, max: 12, step: 1), shortName: "UV",
                         boundStyle: .maxOnly, gradient: .dangerHigh, presetMax: 8),
        MetricDescriptor(key: "moon", displayName: "Moon Phase", unit: "",
                         iconSymbol: "moon.stars.fill", kind: .displayOnly, pro: false,
                         range: nil, shortName: "Moon"),
        MetricDescriptor(key: "dustAlert", displayName: "Dust Alert", unit: "",
                         iconSymbol: "sun.dust.fill", kind: .flag, pro: false,
                         range: nil, shortName: "Dust"),
    ]
}
