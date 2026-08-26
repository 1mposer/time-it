import Foundation

/// What a gradient stop paints: one of the three tiers, or the yellow BLEND
/// WAYPOINT (Semantic `rating/blend`) inserted only at green↔orange hour
/// boundaries. Yellow is not a fourth tier — `HourTier` stays three cases,
/// and every solid-fill/chip/phrase surface types on `HourTier`, so yellow is
/// unreachable outside this stop model by construction.
enum SliceStopColor: Equatable, Hashable {
    case tier(HourTier)
    case blend
}

/// One color stop of the gradient slice: a stop color at a normalized
/// position (0...1) along the range. `color` maps to an actual color
/// elsewhere (ADR-0008 — colors live in Figma/Theme; the one code home is
/// `Theme.sliceStops(for:)`).
struct GradientStop: Equatable {
    let color: SliceStopColor
    let location: Double
}

/// Stop placement for the truthful per-hour gradient slice: each hour
/// contributes one stop at its midpoint — `(i + 0.5) / n` — so its true
/// color shows at its center and blends only across hour boundaries; edge
/// stops at 0 and 1 repeat the first/last tier so the slice starts and ends
/// in a real color. An all-bad range therefore renders solid red with no
/// special case. At every green↔orange boundary a yellow blend waypoint
/// lands exactly on the boundary — `(i + 1) / n` — so the transition passes
/// through yellow instead of the muddy direct green–orange mix; boundaries
/// touching red keep their hard two-stop transition.
enum TierGradient {

    static func stops(for tiers: [HourTier]) -> [GradientStop] {
        guard let first = tiers.first, let last = tiers.last else { return [] }
        let count = Double(tiers.count)

        var stops = [GradientStop(color: .tier(first), location: 0)]
        for (index, tier) in tiers.enumerated() {
            stops.append(GradientStop(color: .tier(tier), location: (Double(index) + 0.5) / count))
            if index + 1 < tiers.count, isBlendBoundary(tier, tiers[index + 1]) {
                stops.append(GradientStop(color: .blend, location: (Double(index) + 1) / count))
            }
        }
        stops.append(GradientStop(color: .tier(last), location: 1))
        return stops
    }

    private static func isBlendBoundary(_ a: HourTier, _ b: HourTier) -> Bool {
        (a == .green && b == .orange) || (a == .orange && b == .green)
    }
}
