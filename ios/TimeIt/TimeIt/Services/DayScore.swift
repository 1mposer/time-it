import Foundation

/// The client-side per-hour score mirror — ADR-0011's depth-in-band formula.
///
/// **No production surface consumes it yet.** The approved frames resolved
/// the detail hero to the WIRE's per-day `score` (86/Perfect holds fixed
/// across the 6am and 7am frames while the hour moves), so nothing on screen
/// currently needs a per-hour number. It ships because ADR-0011's client rule
/// names this mirror explicitly and the spec requires it fixture-pinned on
/// both sides — ready for a per-hour-score surface, and already bound to the
/// server so it cannot drift while it waits. Keeping or deleting it is an
/// owner call, not this change's.
///
/// **This is mirror #4 under [ADR-0007](docs/adr/0007-client-side-mirrors.md)**
/// (alongside `StaticMetricCatalog`, `RangeText` and `HourQuality`): the wire
/// carries only the per-DAY `score`, and ADR-0011's client rule accepts a
/// bounded client recomputation for the per-hour numbers. Any change to the
/// formula lands in BOTH engines (`src/decision/score.js`) in the same wave.
/// The pinning table is `tests/fixtures/day-score-examples.json` — transcribed
/// into `DayScoreMirrorTests` the way `RangeTextTests` transcribes
/// `clock-labels.json`.
///
/// The DAY score is never computed here: it is read from the wire
/// (`Day.score`). Recomputing it on device would duplicate the Window search
/// and night-stitch that ADR-0002 keeps server-only.
///
/// **Recorded asymmetry** (the ADR-0007 mirror-#3 pattern): on a KIND-
/// MISMATCHED threshold/value pair — a flag threshold over a numeric value,
/// or numeric bounds over a boolean — the server scores 100 where this mirror
/// scores 0 (and zeroes the hour when the threshold is `required`).
/// Unreachable on the wire (a kind mismatch is a server `400`, ADR-0005 §6)
/// and unreachable through the wizard (`validationIssues` rejects it), and
/// deliberately NOT aligned: the server's 100 there is an artefact of a
/// comparison that cannot judge, and copying it would make the mirror mimic
/// an error state instead of failing closed. This is part of the mirror's
/// mental model, not a drift bug.
enum DayScore {

    /// Depth-in-band score `0...100` for one threshold/value pair — the
    /// innermost rule of ADR-0011. Required-ness plays no part at this level.
    ///
    /// - Two-sided numeric band: linear, `100` at the band centre, `0` at
    ///   either edge, `0` outside. A **zero-width** band (`min == max`) has
    ///   no centre, so it takes the one-sided binary fallback below: the
    ///   bound value scores `100`, everything else `0`.
    /// - One-sided numeric band (`min`-only / `max`-only): **binary** — the
    ///   note's "centre" is undefined, so `100` inside, `0` outside
    ///   (ADR-0011's recorded simplification).
    /// - Flag (`forbidTrue`): `false` → `100`, `true` → `0`.
    /// - Missing data: `0` (the B2 rule — absent data never passes silently).
    static func metricScore(threshold: Threshold, value: MetricValue) -> Double {
        if threshold.isFlag {
            guard case .flag(let raised) = value else { return 0 }
            return threshold.forbidTrue == true && raised ? 0 : 100
        }
        guard case .number(let number) = value else { return 0 }

        switch (threshold.min, threshold.max) {
        case let (min?, max?):
            // A ZERO-WIDTH band (min == max) has no centre to measure depth
            // from — the very problem the ADR's one-sided case has — so it
            // takes the same BINARY fallback: 100 inside, 0 outside. With
            // min == max "inside" is only the bound value itself, which
            // passes the inclusive comparison. Reachable on the wire:
            // validation rejects min > max, never min == max.
            guard max > min else { return number == min ? 100 : 0 }
            guard number >= min, number <= max else { return 0 }
            let centre = (min + max) / 2
            let halfWidth = (max - min) / 2
            return 100 * (1 - abs(number - centre) / halfWidth)
        case let (min?, nil):
            return number >= min ? 100 : 0
        case let (nil, max?):
            return number <= max ? 100 : 0
        case (nil, nil):
            // Validation-unreachable: a numeric threshold must carry at
            // least one bound (rejected client- AND server-side). Aligned
            // with the server anyway so the mirror never silently disagrees
            // with its reference of record — with no bound to fail,
            // checkThreshold passes and the non-two-sided branch scores 100.
            return 100
        }
    }

    /// The hour's score `0...100`: the mean over the activity's THRESHOLDED
    /// metrics only (display-only metrics never contribute), with a
    /// `required` miss zeroing the whole hour.
    ///
    /// The required-miss test is the threshold's PASS/FAIL predicate
    /// (`HourQuality`'s inclusive-bound semantics), never `metricScore == 0`:
    /// a value sitting exactly on a bound scores `0` for depth yet PASSES its
    /// threshold, so keying the zeroing on the depth score would wrongly kill
    /// every at-bound required hour.
    ///
    /// An activity with no thresholds (show-but-don't-judge) has no mean to
    /// take — it scores `100`, matching `HourQuality`'s "an empty profile
    /// passes".
    static func hourScore(values: [String: MetricValue], thresholds: [String: Threshold]) -> Double {
        guard !thresholds.isEmpty else { return 100 }

        var total: Double = 0
        for (metric, threshold) in thresholds {
            let value = values[metric] ?? .missing
            if threshold.required, !passes(threshold: threshold, value: value) {
                return 0
            }
            total += metricScore(threshold: threshold, value: value)
        }
        return total / Double(thresholds.count)
    }

    /// Convenience over a decoded forecast hour — the shape the views hold.
    static func hourScore(for hour: HourlyWeather, thresholds: [String: Threshold]) -> Double {
        var values: [String: MetricValue] = [:]
        for metric in thresholds.keys {
            values[metric] = MetricValue(metric: metric, hour: hour)
        }
        return hourScore(values: values, thresholds: thresholds)
    }

    /// The pass/fail predicate behind the required-miss rule — the same
    /// inclusive-bound semantics as `HourQuality.passes` (`< min` / `> max`
    /// fail, so a value ON a bound passes) and the same B2 missing-data rule.
    static func passes(threshold: Threshold, value: MetricValue) -> Bool {
        if threshold.isFlag {
            guard case .flag(let raised) = value else { return false }
            return !(threshold.forbidTrue == true && raised)
        }
        guard case .number(let number) = value else { return false }
        if let min = threshold.min, number < min { return false }
        if let max = threshold.max, number > max { return false }
        return true
    }
}

/// One metric's reading for an hour: a number, a flag, or nothing at all.
/// Keeps the "absent fails" rule explicit instead of smuggling it through a
/// double-optional.
enum MetricValue: Equatable {
    case number(Double)
    case flag(Bool)
    case missing

    /// Reads a metric off a decoded hour. Flags come from the boolean wire
    /// fields; everything else from the numeric table. An unknown metric is
    /// `.missing` — and therefore fails, like the server's undefined lookup.
    init(metric: String, hour: HourlyWeather) {
        switch metric {
        case "dustAlert": self = .flag(hour.dustAlert)
        case "seaWarning": self = .flag(hour.seaWarning)
        default:
            if let number = hour.numericValue(for: metric) {
                self = .number(number)
            } else {
                self = .missing
            }
        }
    }
}
