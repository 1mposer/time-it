import Foundation

/// Position math for the detail week's range-zoomed axis: where a day's
/// COVERED range hours sit on the shared [0, 1] axis whose full span is the
/// Range. A day whose forecast covers only part of the Range (partial day 0,
/// horizon tail, nocturnal tail night) paints only its true sub-span —
/// stretching fewer tiers across the full width would fabricate verdicts for
/// hours that have no data.
enum RangeAxis {

    /// The Range's slot count — `(end − start + 24) % 24`, the wrap-safe
    /// duration (`RangeText.axisLabels` speaks the same formula).
    static func slotCount(_ window: WindowSpec) -> Int {
        (window.endHour - window.startHour + 24) % 24
    }

    /// The axis fraction the covered range hours occupy. Each local hour maps
    /// to slot `(hour − start + 24) % 24` of `slotCount`; forecast hours are
    /// contiguous, so the covered slots form one run from the first slot's
    /// leading edge to the last slot's trailing edge. Nil when nothing is
    /// covered, or when an hour falls outside the Range (inputs disagree —
    /// paint nothing rather than lie).
    static func coverageSpan(window: WindowSpec, localHours: [Int]) -> Range<Double>? {
        let count = slotCount(window)
        guard count > 0, !localHours.isEmpty else { return nil }
        let slots = localHours.map { ($0 - window.startHour + 24) % 24 }
        guard slots.allSatisfy({ $0 < count }),
              let first = slots.min(), let last = slots.max() else { return nil }
        return Double(first) / Double(count) ..< Double(last + 1) / Double(count)
    }
}

/// What the detail week bar paints — the decision table for it. Red is
/// reserved for BAD-WITH-DATA (the rule the card already follows): an
/// uncovered Range shows the plain track, and a rated day's gradient paints
/// only over its covered sub-span at true clock position.
enum DayBarPaint: Equatable {
    /// No covered range hours and no verdict — plain track, nothing painted.
    case track
    /// Server `rating: null` over hours that exist: solid red, full width.
    case solidRed
    /// Rated day with no mirror data (authored-lookup miss) — the flat
    /// server-verdict fill.
    case flat
    /// Rated day: one gradient stop per covered hour, over `span`.
    case slice(span: Range<Double>, tiers: [HourTier])

    static func decide(rating: String?, tiers: [HourTier], coverage: Range<Double>?) -> DayBarPaint {
        guard rating != nil else {
            return coverage == nil && tiers.isEmpty ? .track : .solidRed
        }
        guard let coverage, !tiers.isEmpty else { return .flat }
        return .slice(span: coverage, tiers: tiers)
    }
}
