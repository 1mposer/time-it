import Foundation

/// Position math for the detail v3 metric card's threshold gauge: the track
/// is the metric's DOMAIN, the tinted band is the user's threshold, and the
/// dot is the selected hour's value. Pure — the view owns the pixels.
///
/// The domain is the catalog's `MetricRange` (the same table the threshold
/// slider edits against) rather than a second gauge-only table — one home per
/// value, ADR-0009.
enum MetricGauge {

    /// A value's normalised 0...1 position in the metric's domain, clamped so
    /// an out-of-domain reading sits on the track end rather than off it.
    static func position(_ value: Double, in domain: MetricRange) -> Double {
        let span = domain.max - domain.min
        guard span > 0 else { return 0 }
        return Swift.min(Swift.max((value - domain.min) / span, 0), 1)
    }

    /// The threshold band as a normalised span. An unbounded end falls back
    /// to the domain's own end — so a `max`-only threshold reads as a band
    /// that starts at the domain minimum, exactly as the frames draw it.
    /// Nil for a flag threshold (nothing to place on a numeric track).
    static func bandSpan(threshold: Threshold, in domain: MetricRange) -> Range<Double>? {
        guard !threshold.isFlag else { return nil }
        let lower = position(threshold.min ?? domain.min, in: domain)
        let upper = position(threshold.max ?? domain.max, in: domain)
        guard upper > lower else { return lower..<lower }
        return lower..<upper
    }

    /// The numerals printed under the band's two edges — the user's own
    /// bounds, with an unbounded end showing the domain's end (the frames:
    /// "15"/"35" for a two-sided temp band, "0"/"15" for a `max`-only wind).
    static func bandBounds(threshold: Threshold, in domain: MetricRange) -> (lower: Double, upper: Double)? {
        guard !threshold.isFlag else { return nil }
        return (threshold.min ?? domain.min, threshold.max ?? domain.max)
    }

    /// Band/bound numerals as display text, converted through the display
    /// unit the way the threshold editor does — a knots user must not read a
    /// km/h band bound under a knots value. `factor` comes from
    /// `displayFactor(for:windUnit:)`; the conversion and its rounding route
    /// through `ThresholdSlider.displayText` so the gauge and the editor can
    /// never print different numbers for the same stored bound.
    static func boundText(_ value: Double, factor: Double = 1) -> String {
        ThresholdSlider.displayText(value, factor: factor)
    }

    /// 1 for every metric except wind speed shown in knots — the
    /// `ThresholdSlider.displayFactor` rule, shared rather than re-derived.
    /// Only the NUMERALS convert: the gauge's geometry is a ratio of the
    /// metric's domain, so it is unit-free and stays in wire units.
    static func displayFactor(for metric: String, windUnit: WindSpeedUnit) -> Double {
        metric == "windSpeed" ? windUnit.factorFromKmh : 1
    }

    /// The minimum centre-to-centre gap between the two bound numerals, and
    /// the inset that keeps either one from hanging off the track.
    static let numeralGap: Double = 20
    static let numeralInset: Double = 9

    /// Where the two bound numerals are centred, in track points. Both are
    /// kept on the track, and a band too narrow to separate them (a 0–0.2 mm
    /// rainfall threshold on a 0–20 mm domain) has them pushed apart instead
    /// of overprinted — "0" and "0.2", never "002".
    static func numeralPositions(lower: Double,
                                 upper: Double,
                                 trackWidth: Double) -> (lower: Double, upper: Double) {
        let low = Swift.min(Swift.max(lower * trackWidth, numeralInset), trackWidth - numeralInset)
        var high = Swift.min(Swift.max(upper * trackWidth, numeralInset), trackWidth - numeralInset)
        if high - low < numeralGap {
            high = Swift.min(low + numeralGap, trackWidth - numeralInset)
        }
        // If even that collides (a hair-thin track), drop the lower one left.
        let adjustedLow = high - low < numeralGap
            ? Swift.max(high - numeralGap, numeralInset)
            : low
        return (lower: adjustedLow, upper: high)
    }
}
