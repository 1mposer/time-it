import SwiftUI

extension Color {
    /// e.g. Color(hex: 0x1253a4)
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
}

/// Shipped colour tokens — the shipped-truth home (ADR-0009 two-home rule);
/// Figma holds design truth, docs carry no values.
enum Theme {
    static let appBackground = Color(hex: 0xf2f2f7)
    static let cardBackground = Color.white
    static let primaryText = Color(hex: 0x1c1c1e)
    static let secondaryText = Color(hex: 0x8e8e93)
    static let accentOrange = Color(hex: 0xff9500)   // Semantic rating/good
    static let perfectGreen = Color(hex: 0x34c759)   // Semantic rating/perfect
    static let badRed = Color(hex: 0xff3b30)         // Semantic rating/bad — gradient red; gray track = no data only
    static let blendYellow = Color(hex: 0xffbe0a)    // Semantic rating/blend — G↔O waypoint only, never a tier fill (light value; dark wave deferred)
    static let timelineTrack = Color(hex: 0xf2f2f7)
    static let accentInteractive = Color(hex: 0x007aff) // Semantic accent/interactive
    static let divider = Color(hex: 0x3c3c43, opacity: 0.18)

    /// HourTier → rating color binding for the gradient slice (Semantic
    /// rating/perfect · rating/good · rating/bad).
    static func tierColor(_ tier: HourTier) -> Color {
        switch tier {
        case .green: return perfectGreen
        case .orange: return accentOrange
        case .red: return badRed
        }
    }

    /// Single home for the stop→color binding — the card timeline and detail
    /// week rows both route through here, so the yellow-waypoint rule
    /// (`TierGradient`) lives in exactly one place.
    static func sliceStops(for tiers: [HourTier]) -> [Gradient.Stop] {
        TierGradient.stops(for: tiers).map { stop in
            Gradient.Stop(color: color(for: stop.color), location: stop.location)
        }
    }

    private static func color(for stopColor: SliceStopColor) -> Color {
        switch stopColor {
        case .tier(let tier): return tierColor(tier)
        case .blend: return blendYellow
        }
    }

    /// Ocean blue header gradient, #1253a4 → #3ec6e8 at ~160°.
    static let headerGradient = LinearGradient(
        colors: [
            Color(hex: 0x1253a4),
            Color(hex: 0x1a78c2),
            Color(hex: 0x29a8e0),
            Color(hex: 0x3ec6e8),
        ],
        startPoint: UnitPoint(x: 0.33, y: 0),
        endPoint: UnitPoint(x: 0.67, y: 1)
    )
}
