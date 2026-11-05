import SwiftUI

/// One 176pt square metric card of Activity Detail v3 (Figma `464:2321` /
/// `464:2330` / `464:2339`): glyph, metric name, the SELECTED hour's value
/// coloured by that hour's verdict for this metric, and a threshold gauge —
/// track = the metric's domain, tinted band = the user's threshold, dot = the
/// hour's value, with the band's bound numerals underneath.
///
/// `verdict == nil` renders the value and dot UNCOLOURED — the state the
/// stepper's out-of-Range walk uses (owner ruling 2026-09-30: values still
/// shown, just not judged), and also the honest rendering of a metric the
/// Activity shows but does not threshold.
struct MetricCardView: View {
    let metric: String
    /// The selected hour; nil when the forecast has nothing for it.
    let hour: HourlyWeather?
    /// The user's threshold for this metric; nil = show-but-don't-judge.
    let threshold: Threshold?
    /// This hour's verdict for this metric; nil = render uncoloured.
    let verdict: HourTier?
    var catalog: MetricCatalogProviding = StaticMetricCatalog()
    var windUnit: WindSpeedUnit = .kmh

    private static let trackWidth: CGFloat = 136
    private static let trackHeight: CGFloat = 4
    private static let dotSize: CGFloat = 12

    private var descriptor: MetricDescriptor? { catalog.descriptor(for: metric) }
    private var domain: MetricRange? { descriptor?.range }

    private var valueColor: Color {
        guard let verdict else { return Theme.primaryText }
        switch verdict {
        case .green: return Theme.chipTextColor(.green)
        case .orange: return Theme.chipTextColor(.orange)
        case .red: return Theme.chipTextColor(.red)
        }
    }

    private var dotColor: Color {
        guard let verdict else { return Theme.secondaryText }
        return Theme.tierColor(verdict)
    }

    private var valueText: String {
        hour?.formatted(for: metric, windUnit: windUnit) ?? "—"
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Dynamic Type (owner ruling 8): the glyph scales with the value's
    // title2. The gauge — track, band, dot AND its bound numerals — stays
    // fixed (ruling 9a: the strip-like pieces never scale, their numerals
    // may clamp): the numerals' anti-collision gap (`MetricGauge`) is sized
    // for the 10pt glyphs on the fixed 136pt track, so scaled numerals
    // would overprint each other on a narrow band.
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 22
    private static let numeralSlot: CGFloat = 12

    /// Figma detail frame card (176 square, inset 20): glyph 22 at y25, name
    /// 12 at y55, value Semibold 22 at y79, track at y128, band labels 10pt
    /// at y140 — the gauge block is bottom-anchored 24 from the edge.
    var body: some View {
        VStack(spacing: 0) {
            ActivityIconView(identifier: catalog.iconSymbol(for: metric), size: glyphSize)
                .foregroundStyle(Theme.primaryText.opacity(0.75))
                .frame(height: glyphSize)
                .padding(.top, 25)
                .accessibilityHidden(true)
            Text(catalog.displayName(for: metric))
                .scaledFont(size: 12)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, Theme.Spacing.sm)
            Text(valueText)
                .scaledFont(size: 22, weight: .semibold)
                .tracking(-0.4)
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                // The value rolls as the carousel's span settles — the
                // animation rides on the value itself, since a user scroll
                // carries no animation transaction.
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : Theme.Motion.value, value: valueText)
                .padding(.top, Theme.Spacing.md)
            Spacer(minLength: Theme.Spacing.sm)
            gauge
                .padding(.bottom, 24)
        }
        .padding(.horizontal, Theme.Detail.metricInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .cardLift(cornerRadius: Theme.Radius.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("detail.metric.\(metric)")
        .accessibilityLabel("\(catalog.displayName(for: metric)): \(valueText)")
    }

    /// Gauge only where a numeric domain exists — a flag or display-only
    /// metric (dustAlert, moon) has nothing to place on a track.
    @ViewBuilder
    private var gauge: some View {
        if domain == nil {
            // No gauge, but its slot is kept: every card in a grid row then
            // has the same intrinsic height at any text size, so a taller-
            // than-square row never mismatches its two cards.
            Color.clear
                .frame(height: Self.dotSize + 4 + Self.numeralSlot)
        } else if let domain {
            VStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.timelineTrack)
                        .frame(width: Self.trackWidth, height: Self.trackHeight)
                    if let threshold, let span = MetricGauge.bandSpan(threshold: threshold, in: domain) {
                        RoundedRectangle(cornerRadius: 3)
                            // Always the "your band" green tint, whatever the
                            // verdict — the band is the ASK, not the answer.
                            .fill(Theme.perfectGreen.opacity(0.18))
                            .frame(width: max((span.upperBound - span.lowerBound) * Self.trackWidth, 6),
                                   height: 10)
                            .offset(x: span.lowerBound * Self.trackWidth)
                    }
                    if let value = hour?.numericValue(for: metric) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: Self.dotSize, height: Self.dotSize)
                            .offset(x: dotOffset(for: value, in: domain))
                    }
                }
                .frame(width: Self.trackWidth, height: Self.dotSize)
                boundNumerals(domain)
                    .frame(width: Self.trackWidth, height: Self.numeralSlot)
            }
        }
    }

    /// The dot's leading edge, clamped so a domain-edge value sits ON the
    /// track rather than hanging off it (the frames' 0 mm rain dot).
    private func dotOffset(for value: Double, in domain: MetricRange) -> CGFloat {
        let centre = MetricGauge.position(value, in: domain) * Self.trackWidth
        return min(max(centre - Self.dotSize / 2, 0), Self.trackWidth - Self.dotSize)
    }

    /// The band's own bounds, printed under its two edges. A narrow band
    /// (e.g. a 0–0.2 mm rainfall threshold on a 0–20 mm domain) would stack
    /// the two numerals on top of each other, so they are pushed apart to a
    /// minimum legible gap rather than overprinted.
    @ViewBuilder
    private func boundNumerals(_ domain: MetricRange) -> some View {
        if let threshold,
           let bounds = MetricGauge.bandBounds(threshold: threshold, in: domain),
           let span = MetricGauge.bandSpan(threshold: threshold, in: domain) {
            let placed = MetricGauge.numeralPositions(lower: span.lowerBound,
                                                      upper: span.upperBound,
                                                      trackWidth: Double(Self.trackWidth))
            // Numerals convert to the display unit; the geometry above does
            // not (it is a ratio of the domain, so it is unit-free).
            let factor = MetricGauge.displayFactor(for: metric, windUnit: windUnit)
            ZStack(alignment: .leading) {
                numeral(MetricGauge.boundText(bounds.lower, factor: factor), atX: placed.lower)
                numeral(MetricGauge.boundText(bounds.upper, factor: factor), atX: placed.upper)
            }
            .frame(width: Self.trackWidth, alignment: .leading)
        }
    }

    private func numeral(_ text: String, atX x: Double) -> some View {
        Text(text)
            .font(.system(size: 10))
            .tracking(0.1)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize()
            .position(x: CGFloat(x), y: Self.numeralSlot / 2)
    }
}

#if DEBUG
#Preview("Metric cards") {
    let hour = Fixtures_MetricCardPreview.hour
    HStack(spacing: 13) {
        MetricCardView(metric: "temp",
                       hour: hour,
                       threshold: Threshold(min: 15, max: 35, required: true),
                       verdict: .green)
            .atLeastSquare()
        MetricCardView(metric: "windSpeed",
                       hour: hour,
                       threshold: Threshold(max: 15, required: false),
                       verdict: .orange)
            .atLeastSquare()
    }
    .padding(14)
    .background(Theme.appBackground)
}

/// Preview-only hour (the test target's Fixtures are not visible here).
enum Fixtures_MetricCardPreview {
    static let hour = HourlyWeather(index: 0, temp: 24, humidity: 40, visibility: 10,
                                    uV: 3, windSpeed: 27, rainFall: 0, cloudCover: 15,
                                    moon: [], dustAlert: false, seaWarning: false,
                                    darkness: 0, douglasScale: 0, swellHeight: 0,
                                    swellLength: 0, tide: 0)
}
#endif
