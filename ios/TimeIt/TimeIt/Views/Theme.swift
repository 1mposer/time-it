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

        // The hero (owner ruling 2026-11-04): ring 64 inset 16 from the
        // top/left, the rating word 12 under it, 16 to the bottom
        // (16 + 64 + 12 + 14 + 16 = 122). The height is the TALLER of the
        // ring column and the row column, plus the insets — see `heroHeight`.
        static let heroInset: CGFloat = Spacing.card
        static let heroBottom: CGFloat = Spacing.xl
        static let ringDiameter: CGFloat = 64
        static let ringNumeral: CGFloat = 24
        /// The 6pt stroke of the 80pt ring, scaled to 64 (6 × 0.8 ≈ 5).
        static let ringStroke: CGFloat = 5
        static let ringToWord: CGFloat = 12
        /// The rating word's line (Semibold 12).
        static let wordHeight: CGFloat = 14
        /// Ring + gap + word.
        static let ringColumnHeight: CGFloat = ringDiameter + ringToWord + wordHeight

        // The line under the pill row: 13pt, `space/sm` below the row, as tall
        // as its return button so the block never jumps when it appears.
        static let rowToLine: CGFloat = Spacing.sm
        static let lineFont: CGFloat = 13
        static let returnPiece: CGFloat = 24
        static let lineHeight: CGFloat = returnPiece

        /// The pill row (+ the line under it) as one block.
        static func rowColumnHeight(hasLine: Bool) -> CGFloat {
            hasLine ? pillHeight + rowToLine + lineHeight : pillHeight
        }

        /// Where the row block starts below the hero's top inset: alone, the
        /// row sits level with the ring's centre line; with the line, the
        /// block centres on the ring column.
        static func rowColumnTop(hasLine: Bool) -> CGFloat {
            hasLine ? (ringColumnHeight - rowColumnHeight(hasLine: true)) / 2
                    : (ringDiameter - pillHeight) / 2
        }

        /// The hero's height: the taller column plus the insets.
        static func heroHeight(hasLine: Bool) -> CGFloat {
            let row = rowColumnTop(hasLine: hasLine) + rowColumnHeight(hasLine: hasLine)
            return heroInset + Swift.max(ringColumnHeight, row) + heroBottom
        }

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

    /// The dashboard band melt (Figma Final – Opus v1, `839:3930` light /
    /// `839:4160` dark): the header band holds full strength down to the
    /// first list item's top, then melts to the plain ground. Geometry math
    /// lives in `FadeGeometry`; this is the values' only home (ADR-0009).
    enum Fade {
        /// Where the melt reaches 0%, below the first card's top. Owner-
        /// tunable — the owner may still carry it lower; the intermediate
        /// stops scale with it so the curve keeps its shape.
        static let endBelowFirstCard: CGFloat = 111

        /// The Figma melt's span (y229 → y340) — the unit `maskOffsets` is
        /// written in. Fixed: tune `endBelowFirstCard`, never this.
        static let referenceSpan: CGFloat = 111

        /// The mask's alpha stops, as offsets below the first card's top in
        /// `referenceSpan` units (Figma y229 → 229/250/274/298/320/340).
        /// `FadeGeometry` scales them by `endBelowFirstCard / referenceSpan`.
        static let maskOffsets: [(offset: CGFloat, opacity: Double)] = [
            (0, 1), (21, 0.80), (45, 0.52), (69, 0.26), (91, 0.08), (referenceSpan, 0),
        ]

        /// The band's axis in the group's unit space — mostly vertical with
        /// a slight rightward lean (≈19° off vertical).
        static let bandStart = UnitPoint(x: 0.33, y: 0.03)
        static let bandEnd = UnitPoint(x: 0.66, y: 0.98)

        /// `gradient/<set>/start` and `/end` as hex.
        struct BandHex: Equatable {
            let start: UInt32
            let end: UInt32
        }

        static func bandHex(_ band: HeaderBand, dark: Bool) -> BandHex {
            switch (band, dark) {
            case (.cool, false): return BandHex(start: 0x1774ff, end: 0x68d7fc)
            case (.mid, false): return BandHex(start: 0xe49b23, end: 0xf3ca5d)
            case (.hot, false): return BandHex(start: 0xee6a4d, end: 0xfa9c86)
            case (.cool, true): return BandHex(start: 0x1a5fd6, end: 0x2690b8)
            case (.mid, true): return BandHex(start: 0xb26414, end: 0xd4992a)
            case (.hot, true): return BandHex(start: 0xc24a2c, end: 0xc86a50)
            }
        }

        // The glow blob (inside the masked group, so the melt tapers it).
        /// Top-left relative to the group's left edge and the first card's
        /// top (Figma (−90, 150) with the card at 229).
        static let blobOrigin = CGPoint(x: -90, y: -79)
        static let blobSizeLight = CGSize(width: 400, height: 300)
        static let blobSizeDark = CGSize(width: 300, height: 240)
        /// Light fills with the band's start at 85%; dark with its end at 100%.
        static let blobOpacityLight: Double = 0.85
        static let blobOpacityDark: Double = 1
        /// Figma layer blur 80 → SwiftUI blur radius 40 (SwiftUI's radius is
        /// about half a Figma blur — the `cardFloat` convention).
        static let blobBlur: CGFloat = 40

        // The drift: a slow ping-pong between keyframes A and B.
        /// Keyframe B − keyframe A.
        static let driftDelta = CGSize(width: 90, height: 25)
        /// One leg (A→B or B→A), in seconds.
        static let driftLeg: TimeInterval = 30
        /// The drift moves ~3pt/s, so 20 redraws a second is sub-point
        /// motion — no need to redraw at the display's full rate.
        static let driftFrameInterval: TimeInterval = 1.0 / 20

        // The header numeral's readability over the lighter melt.
        /// Ellipse 240×130 at (76.5, 61) on the 393 frame — centred on the
        /// numeral; black 10%, Figma blur 40 → SwiftUI 20.
        static let scrimSize = CGSize(width: 240, height: 130)
        static let scrimOpacity: Double = 0.10
        static let scrimBlur: CGFloat = 20
        /// Figma drop shadow radius 6, black 30% → SwiftUI radius 3.
        static let numeralShadowOpacity: Double = 0.30
        static let numeralShadowRadius: CGFloat = 3

        /// The ground under the melt. Dark is black; light is the existing
        /// grey (`appBackground`). The app is light-only today
        /// (`UIUserInterfaceStyle = Light`), so the dark values are staged.
        static func ground(dark: Bool) -> Color {
            dark ? .black : Theme.appBackground
        }
    }
}

extension View {
    /// Figma "Card Float" elevation.
    func cardFloat() -> some View {
        shadow(color: Theme.cardFloatColor, radius: Theme.cardFloatRadius, x: 0, y: Theme.cardFloatY)
    }
}
