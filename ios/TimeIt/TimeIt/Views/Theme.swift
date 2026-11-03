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

    /// The Figma Layout collection's spacing scale (`space/*`) — the
    /// shipped-truth home for these values (ADR-0009).
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 16
        /// The card padding token.
        static let card: CGFloat = 16
    }

    /// The Figma corner radii.
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        /// Cards and the detail hero.
        static let lg: CGFloat = 16
        static let full: CGFloat = 999
    }

    /// Activity Detail geometry from the Figma detail frame (393pt screen).
    /// Values off the scale above are the frame's own measured gaps.
    enum Detail {
        /// Side margin for the hero and the cards.
        static let sideMargin: CGFloat = Spacing.lg
        /// Nav bar → week-dot row.
        static let topPadding: CGFloat = 12
        /// Week-dot row → hero.
        static let dotsToHero: CGFloat = Spacing.md
        /// Hero → metric grid, and the grid's own row gap.
        static let sectionGap: CGFloat = 12
        static let gridRowGap: CGFloat = 12
        static let gridColumnGap: CGFloat = 13

        // The hero: ring 80 inset 16 from top/left, the rating word 12
        // under it, 28 of air to the bottom (16 + 80 + 12 + 14 + 28 = 150).
        static let heroInset: CGFloat = Spacing.card
        static let heroBottom: CGFloat = 28
        static let ringDiameter: CGFloat = 80
        static let ringNumeral: CGFloat = 28
        static let ringToWord: CGFloat = 12
        /// Ring right edge → the pill column.
        static let ringToRow: CGFloat = Spacing.xl

        // The pill row: − · viewport · + across the column.
        static let pillHeight: CGFloat = 24
        static let pillGap: CGFloat = 3
        static let stepPiece: CGFloat = 24
        static let stepToViewport: CGFloat = Spacing.xs
        /// Pads the 24pt pieces to the HIG 44pt target.
        static let hitPad: CGFloat = 10

        /// The metric card's inner inset.
        static let metricInset: CGFloat = 20
    }

    /// The detail's motion springs (fluid-interfaces spring table: response
    /// = pace, damping = character; no mass/stiffness).
    enum Motion {
        /// − / + slide the row one pill: tap-triggered, no bounce.
        static let step = Animation.spring(response: 0.35, dampingFraction: 1)
        /// The ring springs the row home — a longer throw, a little life.
        static let home = Animation.spring(response: 0.35, dampingFraction: 0.8)
        /// The metric values' numeric roll and the pills' chosen/dim swap.
        static let value = Animation.spring(response: 0.3, dampingFraction: 1)
        /// A press releasing: instant on, slower off.
        static let pressRelease = Animation.spring(duration: 0.3)
        static let pressScale: CGFloat = 0.97
    }

    /// Light-mode card elevation — Figma "Card Float" (y4, blur 16, black
    /// 6%; SwiftUI's shadow radius is about half a Figma blur).
    static let cardFloatColor = Color.black.opacity(0.06)
    static let cardFloatRadius: CGFloat = 8
    static let cardFloatY: CGFloat = 4

    /// The Range's "home" ghost outline on the detail pill row: 1pt
    /// interactive accent at 35%, inside the pill rect.
    static let homeOutline = accentInteractive.opacity(0.35)
    static let homeOutlineWidth: CGFloat = 1

    /// Metric-chip tier colors — text uses darker high-contrast variants so
    /// the label passes contrast on the 12% tint; backgrounds tint the
    /// semantic rating tokens. The ONLY home for these values (ADR-0009
    /// shipped-truth rule) — never respell a chip hex in a view.
    static func chipTextColor(_ tier: MetricTier) -> Color {
        switch tier {
        case .green: return Color(hex: 0x1a7a35)
        case .orange: return Color(hex: 0xb85c00)
        case .red: return Color(hex: 0xc0392b)
        case .neutral: return Color(hex: 0x636366)
        }
    }

    static func chipBackgroundColor(_ tier: MetricTier) -> Color {
        switch tier {
        case .green: return perfectGreen.opacity(0.12)
        case .orange: return accentOrange.opacity(0.12)
        case .red: return badRed.opacity(0.12)
        case .neutral: return secondaryText.opacity(0.12)
        }
    }

    /// The day's rating tier as a colour — the score ring's arc and numeral,
    /// and the detail hero's rating word (card v2 / detail v3 frames). A null
    /// verdict reads red, and so does an `.unknown` one: a verdict this build
    /// doesn't understand must never paint favourably (2026-08-29 hardening).
    static func ratingTint(_ rating: Rating?) -> Color {
        switch rating {
        case .perfect: return perfectGreen
        case .good: return accentOrange
        default: return badRed
        }
    }

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

    /// The header's temperature band — drives the gradient (Figma: Header,
    /// node 92:11). Delegates to the temp chip's tier table (owner ruling
    /// 2026-09-01: one consistent 33/38 language — a chip-band change must
    /// move the header with it); no reading defaults to Cool.
    enum HeaderBand {
        case cool
        case mid
        case hot

        static func band(forTemp temp: Double?) -> HeaderBand {
            switch MetricTier.tier(for: "temp", value: temp) {
            case .red: return .hot
            case .orange: return .mid
            case .green, .neutral: return .cool
            }
        }
    }

    /// Header gradient by current-hour temperature. Stops sampled from the
    /// Figma header states (Cool blue / Mid amber / Hot salmon — the old
    /// ocean-blue gradient is retired per the design page note).
    static func headerGradient(forTemp temp: Double?) -> LinearGradient {
        let colors: [Color]
        switch HeaderBand.band(forTemp: temp) {
        case .cool:
            colors = [Color(hex: 0x1774ff), Color(hex: 0x3295fd), Color(hex: 0x68d7fc)]
        case .mid:
            colors = [Color(hex: 0xe49b23), Color(hex: 0xe9ab36), Color(hex: 0xf3ca5d)]
        case .hot:
            colors = [Color(hex: 0xee6a4d), Color(hex: 0xf27b60), Color(hex: 0xfa9c86)]
        }
        return LinearGradient(colors: colors,
                              startPoint: UnitPoint(x: 0.33, y: 0),
                              endPoint: UnitPoint(x: 0.67, y: 1))
    }
}

extension View {
    /// Figma "Card Float" elevation.
    func cardFloat() -> some View {
        shadow(color: Theme.cardFloatColor, radius: Theme.cardFloatRadius, x: 0, y: Theme.cardFloatY)
    }
}
