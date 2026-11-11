import SwiftUI
import UIKit

extension Color {
    /// e.g. Color(hex: 0x1253a4)
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }

    /// A light/dark-aware token (Figma Semantic collection, Light → Dark
    /// modes): resolves per trait collection, so every call site follows the
    /// system appearance with no branching of its own.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor.dynamic(light: light, dark: dark,
                                           lightAlpha: lightAlpha, darkAlpha: darkAlpha))
    }
}

extension UIColor {
    /// e.g. UIColor(hex: 0x1253a4, alpha: 0.5) — sRGB, the `Color(hex:)` twin.
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: CGFloat(alpha))
    }

    /// The trait-resolving colour behind `Color(light:dark:)` — the ONE
    /// light/dark helper every token is built on.
    static func dynamic(light: UInt32, dark: UInt32,
                        lightAlpha: Double = 1, darkAlpha: Double = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        }
    }
}

/// Shipped colour tokens — the shipped-truth home (ADR-0009 two-home rule);
/// Figma holds design truth, docs carry no values. Every colour token is
/// light/dark-aware (Figma Semantic, Light → Dark); `Theme.UIColors` holds
/// the same tokens as `UIColor` so tests can resolve them per trait.
enum Theme {
    /// The tokens as resolvable `UIColor`s — the one table both modes read.
    enum UIColors {
        /// surface/background — the owner's dark palette (2026-11-11, round
        /// 4: "background"; it replaced the sage ladder C, which read as "AI
        /// green"). No pure black anywhere in dark.
        static let appBackground = UIColor.dynamic(light: 0xf2f2f7, dark: 0x161915)
        /// surface/card — cards, sheets, tiles (dark "surface").
        static let cardBackground = UIColor.dynamic(light: 0xffffff, dark: 0x222721)
        /// surface/detail-container — every container on the Activity
        /// detail (hero, metric cards, add-metric tile): a darker, calmer
        /// green than `cardBackground` in both modes (owner, build 10 POLISH
        /// item 4). The page ground stays `appBackground`, as on the dashboard.
        static let detailContainer = UIColor.dynamic(light: 0xe5ede7, dark: 0x1c231e)
        static let primaryText = UIColor.dynamic(light: 0x1c1c1e, dark: 0xd7dcd6)          // text/primary
        /// text/secondary — 6.22:1 on the dark ground, 5.34 on the card;
        /// only 4.29 on the dark track, so no secondary text sits on a well.
        static let secondaryText = UIColor.dynamic(light: 0x8e8e93, dark: 0x8f9d8b)
        /// text/on-gradient — white on the temperature band in both modes.
        static let onGradient = UIColor.dynamic(light: 0xffffff, dark: 0xffffff)
        /// text/on-fill — the label on a filled accent control: white in
        /// light, the dark "buttonLabel" (9.27:1 on the dark fill).
        static let onFill = UIColor.dynamic(light: 0xffffff, dark: 0x161915)
        static let ratingGood = UIColor.dynamic(light: 0xff9500, dark: 0xff9f0a)           // rating/good
        static let perfectGreen = UIColor.dynamic(light: 0x34c759, dark: 0x30d158)         // rating/perfect
        static let badRed = UIColor.dynamic(light: 0xff3b30, dark: 0xff453a)               // rating/bad
        static let blendYellow = UIColor.dynamic(light: 0xffbe0a, dark: 0xffbe0a)          // rating/blend (same, intended)
        /// accent/brand — the app's one interactive colour (Q1a, app-wide):
        /// text, icons, rings, selection. Dark is the owner's "main": 9.27:1
        /// on the ground, 7.95 on the card, 6.39 on the track.
        static let accentBrand = UIColor.dynamic(light: 0x48665c, dark: 0xb5beb2)
        /// accent/brand-fill — filled controls; the label is `onFill`.
        static let accentBrandFill = UIColor.dynamic(light: 0x48665c, dark: 0xb5beb2)
        /// The filled control while pressed (dark "buttonPressed"; light has
        /// no ruled pressed colour and keeps the fill).
        static let accentBrandPressed = UIColor.dynamic(light: 0x48665c, dark: 0x8f9d8b)
        /// A disabled fill / inactive control (dark "disabled"); light keeps
        /// the dimmed fill.
        static let disabledFill = UIColor.dynamic(light: 0x48665c, dark: 0x444d41,
                                                  lightAlpha: 0.45, darkAlpha: 1)
        /// The label on a disabled fill — white over light's dimmed fill,
        /// the dark secondary over dark's "disabled" fill (3.09:1; disabled
        /// controls are exempt from 4.5:1 but must stay legible).
        static let disabledLabel = UIColor.dynamic(light: 0xffffff, dark: 0x8f9d8b)
        /// The accent tint behind chips and soft selections — 18% light, 16%
        /// dark (main text on it holds 5.71:1).
        static let accentTint = UIColor.dynamic(light: 0x48665c, dark: 0xb5beb2,
                                                lightAlpha: 0.18, darkAlpha: 0.16)
        static let accentDestructive = UIColor.dynamic(light: 0xff3b30, dark: 0xff453a)    // accent/destructive
        /// timeline/track — tracks, wells, empty hour segments (dark "divider").
        static let timelineTrack = UIColor.dynamic(light: 0xf2f2f7, dark: 0x31372f)
        /// separator — the dark "divider", opaque.
        static let divider = UIColor.dynamic(light: 0x3c3c43, dark: 0x31372f,
                                             lightAlpha: 0.18, darkAlpha: 1)
        /// The cards' 0.5pt hairline — light only; in dark the Card Lift Dark
        /// top highlight replaces it.
        static let cardHairline = UIColor.dynamic(light: 0x000000, dark: 0x000000,
                                                  lightAlpha: 0.06, darkAlpha: 0)

        /// chip/<tier>/text — light: a darker high-contrast variant; dark:
        /// the rating colour itself.
        static func chipText(_ tier: MetricTier) -> UIColor {
            switch tier {
            case .green: return chipGreenText
            case .orange: return chipOrangeText
            case .red: return chipRedText
            case .neutral: return chipNeutralText
            }
        }

        /// chip/<tier>/bg — the rating colour at 12% light, 20% dark.
        static func chipBackground(_ tier: MetricTier) -> UIColor {
            switch tier {
            case .green: return chipGreenBackground
            case .orange: return chipOrangeBackground
            case .red: return chipRedBackground
            case .neutral: return chipNeutralBackground
            }
        }

        private static let chipGreenText = UIColor.dynamic(light: 0x1a7a35, dark: 0x30d158)
        private static let chipOrangeText = UIColor.dynamic(light: 0xb85c00, dark: 0xff9f0a)
        private static let chipRedText = UIColor.dynamic(light: 0xc0392b, dark: 0xff453a)
        private static let chipNeutralText = UIColor.dynamic(light: 0x636366, dark: 0x8f9d8b)
        private static let chipGreenBackground = UIColor.dynamic(light: 0x34c759, dark: 0x30d158,
                                                                 lightAlpha: 0.12, darkAlpha: 0.20)
        private static let chipOrangeBackground = UIColor.dynamic(light: 0xff9500, dark: 0xff9f0a,
                                                                  lightAlpha: 0.12, darkAlpha: 0.20)
        private static let chipRedBackground = UIColor.dynamic(light: 0xff3b30, dark: 0xff453a,
                                                               lightAlpha: 0.12, darkAlpha: 0.20)
        private static let chipNeutralBackground = UIColor.dynamic(light: 0x8e8e93, dark: 0x8f9d8b,
                                                                   lightAlpha: 0.12, darkAlpha: 0.20)
    }

    static let appBackground = Color(uiColor: UIColors.appBackground)
    static let cardBackground = Color(uiColor: UIColors.cardBackground)
    static let detailContainer = Color(uiColor: UIColors.detailContainer)
    static let primaryText = Color(uiColor: UIColors.primaryText)
    static let secondaryText = Color(uiColor: UIColors.secondaryText)
    /// Text and glyphs on the temperature band — white in both modes.
    static let onGradient = Color(uiColor: UIColors.onGradient)
    /// The label on a filled accent control (white light, dark ink dark).
    static let onFill = Color(uiColor: UIColors.onFill)
    static let ratingGood = Color(uiColor: UIColors.ratingGood)       // Semantic rating/good
    static let perfectGreen = Color(uiColor: UIColors.perfectGreen)   // Semantic rating/perfect
    static let badRed = Color(uiColor: UIColors.badRed)               // Semantic rating/bad — gradient red; gray track = no data only
    /// The detail hero's "No Window" word — light red, Regular 12 (owner
    /// ruling 2026-11-04); rated words keep their full `ratingTint`.
    static let noWindowTint = badRed.opacity(0.7)
    static let blendYellow = Color(uiColor: UIColors.blendYellow)     // Semantic rating/blend — G↔O waypoint only, never a tier fill
    static let timelineTrack = Color(uiColor: UIColors.timelineTrack)
    static let accentBrand = Color(uiColor: UIColors.accentBrand)           // Semantic accent/brand
    static let accentBrandFill = Color(uiColor: UIColors.accentBrandFill)   // Semantic accent/brand-fill
    static let accentBrandPressed = Color(uiColor: UIColors.accentBrandPressed)
    static let disabledFill = Color(uiColor: UIColors.disabledFill)
    static let disabledLabel = Color(uiColor: UIColors.disabledLabel)
    static let accentTint = Color(uiColor: UIColors.accentTint)
    static let accentDestructive = Color(uiColor: UIColors.accentDestructive) // Semantic accent/destructive
    static let divider = Color(uiColor: UIColors.divider)
    /// The cards' 0.5pt hairline (light only — clear in dark).
    static let cardHairline = Color(uiColor: UIColors.cardHairline)
    static let cardHairlineWidth: CGFloat = 0.5
    /// Shadows, scrims and drops — black in both modes (they darken; they
    /// are not surfaces).
    static let shadowInk = Color.black
    /// The threshold slider's thumb — white in both modes (the system
    /// slider convention).
    static let sliderThumb = Color.white

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
        /// The card list's resting top below the header — the hero's room to
        /// breathe (owner ruling 2026-11-05: 14 → 18). The melt anchors on
        /// it too (`BandMeltView.firstCardTop`).
        static let listBelowHeader: CGFloat = 14
        /// The gap between cards in the list (the 10pt md token; a 12pt
        /// try on 2026-11-05 was returned).
        static let cardGap: CGFloat = 10
        /// The header's vertical rhythm: location → numeral, numeral → meta
        /// row (the original values; wider tries on 2026-11-05 were returned).
        static let headerLocationToNumeral: CGFloat = 2
        static let headerNumeralToMeta: CGFloat = 10
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
        /// The numeral's Dynamic Type cap — Figma "Score" Semibold 28, the
        /// largest a "100" still fits inside the fixed 64pt ring's stroke.
        static let ringNumeralMax: CGFloat = 28
        /// The 6pt stroke of the 80pt ring, scaled to 64 (6 × 0.8 ≈ 5).
        static let ringStroke: CGFloat = 5
        static let ringToWord: CGFloat = 12
        /// The rating word's line (Semibold 12).
        static let wordHeight: CGFloat = 14
        /// Ring + gap + word — the ring column in every state (owner ruling
        /// 2026-11-04 removed the scored-span caption under the word).
        static let ringColumnHeight: CGFloat = ringDiameter + ringToWord + wordHeight

        // Row 1, the Range line under the pill row: 13pt, `space/sm` below
        // the row, as tall as its return button so the line never jumps when
        // the button appears at its end.
        static let rowToLine: CGFloat = Spacing.sm
        static let lineFont: CGFloat = 13
        static let returnPiece: CGFloat = 24
        static let lineHeight: CGFloat = returnPiece

        // Row 2, the span action row (owner rulings 2026-11-04), `rowToLine`
        // under row 1 and only away from the Range: the glass "Score 7 –
        // 11am" capsule, the quiet "Scored 7 – 11am" text, or the failure
        // note — all in one constant-height slot so nothing below jumps.
        static let spanRowHeight: CGFloat = 28
        static let spanRowFont: CGFloat = 13
        static let spanCapsulePadding: CGFloat = 12
        /// Pads the 28pt capsule's hit area to the HIG 44pt target.
        static let spanRowHitPad: CGFloat = (minHitTarget - spanRowHeight) / 2
        /// The capsule's own glass container blend distance (it is not in
        /// the − / + container, so it never melts into those pieces).
        static let spanCapsuleBlend: CGFloat = 0
        /// The press lift: past rest by this much, then falls back.
        static let liftScale: CGFloat = 1.04
        static let liftRise: CGFloat = -4
        /// The in-flight label dims to this while the server scores the span.
        static let inFlightOpacity: Double = 0.6

        /// The Dynamic Type seam (owner ruling 8, 2026-10-06): the three
        /// text rows the hero stacks — the rating word, row 1 (the Range
        /// line) and row 2 (the span action row) — at the user's text size.
        /// `.standard` is the Figma default-size set, so every function below
        /// reads exactly today's constants unless the view passes the
        /// `@ScaledMetric` values. The ring, the pills and the − / + pieces
        /// never scale (ruling 9a), so they stay plain constants.
        struct HeroMetrics: Equatable {
            var wordHeight: CGFloat
            var lineHeight: CGFloat
            var spanRowHeight: CGFloat

            static let standard = HeroMetrics(wordHeight: Detail.wordHeight,
                                              lineHeight: Detail.lineHeight,
                                              spanRowHeight: Detail.spanRowHeight)

            /// The view's scaled set. Row 1 is never shorter than its return
            /// piece (the line must hold still as the button appears).
            static func scaled(wordHeight: CGFloat, lineHeight: CGFloat, spanRowHeight: CGFloat) -> HeroMetrics {
                HeroMetrics(wordHeight: wordHeight,
                            lineHeight: Swift.max(lineHeight, Detail.returnPiece),
                            spanRowHeight: spanRowHeight)
            }
        }

        /// Ring + gap + word at a text size (`ringColumnHeight` at default).
        static func scaledRingColumnHeight(_ metrics: HeroMetrics) -> CGFloat {
            ringDiameter + ringToWord + metrics.wordHeight
        }

        /// The pill row (+ row 1, the Range line, + row 2, the span action
        /// row) as one block. Row 2 hangs under row 1, so it needs the line.
        static func rowColumnHeight(hasLine: Bool, hasSpanRow: Bool = false,
                                    metrics: HeroMetrics = .standard) -> CGFloat {
            guard hasLine else { return pillHeight }
            let line = pillHeight + rowToLine + metrics.lineHeight
            return hasSpanRow ? line + rowToLine + metrics.spanRowHeight : line
        }

        /// Where the row block starts below the hero's top inset: alone, the
        /// row sits level with the ring's centre line; with the line, the
        /// row + line block centres on the ring column. Row 2 never moves it
        /// — the − / + row the finger is on holds still while row 2 comes and
        /// goes (fluid-interfaces spatial consistency); the hero grows
        /// instead (`heroHeight`). Never negative: at a large text size the
        /// row + line block outgrows the ring column and starts at the top.
        static func rowColumnTop(hasLine: Bool, metrics: HeroMetrics = .standard) -> CGFloat {
            let top = hasLine
                ? (scaledRingColumnHeight(metrics) - rowColumnHeight(hasLine: true, metrics: metrics)) / 2
                : (ringDiameter - pillHeight) / 2
            return Swift.max(top, 0)
        }

        /// The hero's height: the taller column plus the insets — 122 on the
        /// Range (the ring column), 141 away with row 2 (default text size).
        static func heroHeight(hasLine: Bool, hasSpanRow: Bool = false,
                               metrics: HeroMetrics = .standard) -> CGFloat {
            let row = rowColumnTop(hasLine: hasLine, metrics: metrics)
                + rowColumnHeight(hasLine: hasLine, hasSpanRow: hasSpanRow, metrics: metrics)
            return heroInset + Swift.max(scaledRingColumnHeight(metrics), row) + heroBottom
        }

        /// The accessibility-size hero (owner ruling 5, the surviving part):
        /// the ring column on top, `ringToRow` gap, then the row block full
        /// width under it — the pill row's top is fixed under the ring
        /// column, so row 2 still never moves it.
        static func stackedHeroHeight(hasLine: Bool, hasSpanRow: Bool = false,
                                      metrics: HeroMetrics = .standard) -> CGFloat {
            heroInset + scaledRingColumnHeight(metrics) + ringToRow
                + rowColumnHeight(hasLine: hasLine, hasSpanRow: hasSpanRow, metrics: metrics) + heroBottom
        }

        /// The capsule's vertical hit padding at a row-2 height — to the HIG
        /// 44pt, and none once the capsule is itself taller than that.
        static func hitPad(forSpanRowHeight height: CGFloat) -> CGFloat {
            Swift.max((minHitTarget - height) / 2, 0)
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
        /// The HIG minimum hit target.
        static let minHitTarget: CGFloat = 44

        // The edit circles (owner rulings 2026-11-04): two 44pt circles on
        // the ground under the metric grid — a 17pt Semibold glyph, an 11pt
        // secondary caption 6pt below, the pair 32pt apart and centred,
        // 24pt above the pair.
        static let editCircleDiameter: CGFloat = minHitTarget
        static let editCircleGlyph: CGFloat = 17
        static let editCircleToCaption: CGFloat = 6
        static let editCaptionFont: CGFloat = 11
        static let editCircleGap: CGFloat = 32
        static let editCirclesTop: CGFloat = 24
        /// The circles' glass container blend distance — under the gap, so
        /// the two stay two circles rather than melting into one shape.
        static let editCircleBlend: CGFloat = 8

        /// The metric card's inner inset.
        static let metricInset: CGFloat = 20

        /// The metric grid: two columns, one at accessibility sizes (owner
        /// ruling 5's surviving part — reduce columns, don't truncate).
        static func metricGridColumnCount(isAccessibilitySize: Bool) -> Int {
            isAccessibilitySize ? 1 : 2
        }

        /// The square floor belongs to the two-column grid only: there the
        /// cards are square at the default size and a row's two cards match.
        /// A single full-width column takes the content's own height.
        static func metricCardHasSquareFloor(columnCount: Int) -> Bool {
            columnCount > 1
        }
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
        /// The span-score button's "lift and fall" on release (owner ruling
        /// 2026-11-04): a quick rise past rest, then a bouncy fall back.
        static let liftRiseSpring = Spring(response: 0.15, dampingRatio: 1)
        static let liftSpring = Spring(response: 0.4, dampingRatio: 0.6)
        static let lift = Animation.spring(liftSpring)
        /// A tap-driven reveal / de-reveal (the ✕ dismissals, the card
        /// chevron — owner report 2026-11-05): a tap throws nothing, so the
        /// spring is critically damped — no overshoot.
        static let revealDuration: Double = 0.35
        static let revealBounce: Double = 0
        static let reveal = Animation.spring(duration: revealDuration, bounce: revealBounce)
        /// The Reduce Motion stand-in: a cross-fade, never an abrupt removal.
        static let revealReduced = Animation.easeOut(duration: 0.2)
        /// The reveal animation for the current Reduce Motion setting.
        static func reveal(reduceMotion: Bool) -> Animation {
            reduceMotion ? revealReduced : reveal
        }
    }

    /// Light-mode card elevation — Figma "Card Float" (y4, blur 16, black
    /// 6%; SwiftUI's shadow radius is about half a Figma blur).
    static let cardFloatColor = shadowInk.opacity(0.06)
    static let cardFloatRadius: CGFloat = 8
    static let cardFloatY: CGFloat = 4

    /// Light-mode resting card shadow — the dashboard cards' own (black 8%,
    /// r3, y1), lighter than Card Float.
    static let cardRestColor = shadowInk.opacity(0.08)
    static let cardRestRadius: CGFloat = 3
    static let cardRestY: CGFloat = 1

    /// Dark-mode card elevation — Figma "Card Lift Dark": an inner top
    /// highlight (white 6%, y1, blur 0) plus a drop shadow (black 40%, y4,
    /// Figma blur 12 → SwiftUI radius 6). No hairline in dark.
    static let cardLiftHighlight = Color.white.opacity(0.06)
    static let cardLiftHighlightY: CGFloat = 1
    static let cardLiftShadowColor = shadowInk.opacity(0.40)
    static let cardLiftShadowRadius: CGFloat = 6
    static let cardLiftShadowY: CGFloat = 4

    /// The Range's "home" ghost outline on the detail pill row: 1pt
    /// interactive accent at 35%, inside the pill rect.
    static let homeOutline = accentBrand.opacity(0.35)
    static let homeOutlineWidth: CGFloat = 1

    /// Metric-chip tier colors — text uses darker high-contrast variants so
    /// the label passes contrast on the 12% tint; backgrounds tint the
    /// semantic rating tokens. The ONLY home for these values (ADR-0009
    /// shipped-truth rule) — never respell a chip hex in a view.
    static func chipTextColor(_ tier: MetricTier) -> Color {
        switch tier {
        case .green: return chipGreenText
        case .orange: return chipOrangeText
        case .red: return chipRedText
        case .neutral: return chipNeutralText
        }
    }

    static func chipBackgroundColor(_ tier: MetricTier) -> Color {
        switch tier {
        case .green: return chipGreenBackground
        case .orange: return chipOrangeBackground
        case .red: return chipRedBackground
        case .neutral: return chipNeutralBackground
        }
    }

    private static let chipGreenText = Color(uiColor: UIColors.chipText(.green))
    private static let chipOrangeText = Color(uiColor: UIColors.chipText(.orange))
    private static let chipRedText = Color(uiColor: UIColors.chipText(.red))
    private static let chipNeutralText = Color(uiColor: UIColors.chipText(.neutral))
    private static let chipGreenBackground = Color(uiColor: UIColors.chipBackground(.green))
    private static let chipOrangeBackground = Color(uiColor: UIColors.chipBackground(.orange))
    private static let chipRedBackground = Color(uiColor: UIColors.chipBackground(.red))
    private static let chipNeutralBackground = Color(uiColor: UIColors.chipBackground(.neutral))

    /// The day's rating tier as a colour — the score ring's arc and numeral,
    /// and the detail hero's rating word (card v2 / detail v3 frames). A null
    /// verdict reads red, and so does an `.unknown` one: a verdict this build
    /// doesn't understand must never paint favourably (2026-08-29 hardening).
    static func ratingTint(_ rating: Rating?) -> Color {
        switch rating {
        case .perfect: return perfectGreen
        case .good: return ratingGood
        default: return badRed
        }
    }

    /// HourTier → rating color binding for the gradient slice (Semantic
    /// rating/perfect · rating/good · rating/bad).
    static func tierColor(_ tier: HourTier) -> Color {
        switch tier {
        case .green: return perfectGreen
        case .orange: return ratingGood
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

        // The temperature numeral's readability over the lighter melt
        // (ruling 8a; Figma scrims 811:4854 / 811:4855).
        /// Ellipse 240×130 at (76.5, 61) on the 393 frame — centred on the
        /// temperature numeral; black 10%, Figma blur 40 → SwiftUI 20.
        static let scrimSize = CGSize(width: 240, height: 130)
        static let scrimOpacity: Double = 0.10
        static let scrimBlur: CGFloat = 20
        /// The temperature numeral's Figma drop shadow (541:906 / 541:4095):
        /// radius 6 → SwiftUI radius 3, offset y 2, black 30%.
        static let numeralShadowOpacity: Double = 0.30
        static let numeralShadowRadius: CGFloat = 3
        static let numeralShadowY: CGFloat = 2

        /// The ground under the melt — `surface/background` resolved for the
        /// mode (black in dark, the grey `appBackground` in light).
        static func ground(dark: Bool) -> Color {
            Color(uiColor: Theme.UIColors.appBackground.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)))
        }
    }
}

/// Which light-mode shadow a card keeps under `cardLift` — dark is always
/// Card Lift Dark.
enum CardLightElevation {
    /// Figma "Card Float" (the detail hero, the metric cards).
    case float
    /// The dashboard cards' lighter resting shadow.
    case rest
}

/// Card elevation for both modes: light = the chosen light shadow + the
/// 0.5pt hairline; dark = Card Lift Dark (1pt inner top highlight + black
/// 40% drop), no hairline (owner ruling 2026-10-06 #6).
private struct CardLift: ViewModifier {
    let cornerRadius: CGFloat
    let light: CardLightElevation
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if colorScheme == .dark {
            content
                .overlay {
                    // The inner shadow, literally: the card's shape minus
                    // itself moved down 1pt leaves a 1pt crescent along the
                    // top edge that tapers into the corners.
                    shape.subtracting(shape.offset(y: Theme.cardLiftHighlightY))
                        .fill(Theme.cardLiftHighlight)
                        .allowsHitTesting(false)
                }
                .shadow(color: Theme.cardLiftShadowColor, radius: Theme.cardLiftShadowRadius,
                        x: 0, y: Theme.cardLiftShadowY)
        } else {
            switch light {
            case .float:
                content
                    .cardFloat()
                    .overlay(shape.stroke(Theme.cardHairline, lineWidth: Theme.cardHairlineWidth))
            case .rest:
                content
                    .shadow(color: Theme.cardRestColor, radius: Theme.cardRestRadius,
                            x: 0, y: Theme.cardRestY)
                    .overlay(shape.stroke(Theme.cardHairline, lineWidth: Theme.cardHairlineWidth))
            }
        }
    }
}

extension View {
    /// Figma "Card Float" elevation (light mode only — cards use `cardLift`).
    func cardFloat() -> some View {
        shadow(color: Theme.cardFloatColor, radius: Theme.cardFloatRadius, x: 0, y: Theme.cardFloatY)
    }

    /// A card's elevation in either mode — after the card's background and
    /// clip, in place of a shadow + hairline pair.
    func cardLift(cornerRadius: CGFloat, light: CardLightElevation = .float) -> some View {
        modifier(CardLift(cornerRadius: cornerRadius, light: light))
    }
}


// MARK: Grouped lists on the app's ground (owner ruling 18a, 2026-11-11)

extension View {
    /// A `List` / `Form` drawn on the app's ground (its rows take
    /// `appCardRows()`), so Settings and its sheets share every other
    /// screen's ground in dark instead of the system grouped greys.
    func appGroundedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.appBackground.ignoresSafeArea())
    }

    /// Rows on the app's card surface.
    func appCardRows() -> some View { listRowBackground(Theme.cardBackground) }
}
