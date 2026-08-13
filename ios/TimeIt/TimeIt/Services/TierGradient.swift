import Foundation

/// One color stop of the spec 14 §2 gradient slice: a tier at a normalized
/// position (0...1) along the range. The rendering wave maps `tier` to the
/// actual tier color (ADR-0008 — colors live in Figma/Theme, not here).
struct GradientStop: Equatable {
    let tier: HourTier
    let location: Double
}

/// Stop placement for the truthful per-hour gradient slice (spec 14 §2,
/// feasibility I6): each hour contributes one stop at its midpoint —
/// `(i + 0.5) / n` — so its true color shows at its center and blends only
/// across hour boundaries; edge stops at 0 and 1 repeat the first/last tier
/// so the slice starts and ends in a real color. An all-bad range therefore
/// renders solid red with no special case.
enum TierGradient {

    static func stops(for tiers: [HourTier]) -> [GradientStop] {
        guard let first = tiers.first, let last = tiers.last else { return [] }
        let count = Double(tiers.count)

        var stops = [GradientStop(tier: first, location: 0)]
        stops += tiers.enumerated().map { index, tier in
            GradientStop(tier: tier, location: (Double(index) + 0.5) / count)
        }
        stops.append(GradientStop(tier: last, location: 1))
        return stops
    }
}
