import SwiftUI

/// Every number of the lane-RETHINK surfaces (Figma Mess around, row "Edit
/// round 1 — Final - Opus v2", owner-approved 2026-11-16) in one place, so
/// the owner can move things by eye. Owner rule 2026-11-16: every padding,
/// gap and radius sits on Apple's base-4 grid (`Grid`), preferring the
/// 8-multiples; radii nest as outer = inner + padding, and every rounded
/// container is a superellipse (`RoundedRectangle(style: .continuous)`).
enum RethinkLayout {
    /// The base-4 grid. Move a value by picking another step.
    enum Grid {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
        static let x10: CGFloat = 40
        static let x12: CGFloat = 48
    }

    // MARK: The one padding (owner, 2026-11-15)

    /// Inside every container.
    static let inset = Grid.x4
    /// Between containers.
    static let gap = Grid.x4
    /// The page's side margin.
    static let margin = Grid.x4
    /// Rows, the highlight band, the back pill.
    static let innerRadius = Grid.x2
    /// Cards, hero, metric cards, hours-over row, Coming days, overlay:
    /// inner + padding.
    static let outerRadius = innerRadius + inset

    /// The superellipse every rounded container uses.
    static func shape(_ radius: CGFloat = outerRadius) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    // MARK: Dashboard card (frame 1 `921:19890`)

    enum Card {
        /// The ring column: 64 wide, the 48pt ring centred in it.
        static let ringColumnWidth = Grid.x4 * 4
        static let ringDiameter = Grid.x12
        /// Ring → caption (Figma 9 → snapped to 8).
        static let ringToCaption = Grid.x2
        /// Ring column → text column.
        static let columnGap = Grid.x4
        /// Name row → hour bars.
        static let nameToStrip = Grid.x2
        static let stripHeight: CGFloat = 6
        static let stripSegmentGap: CGFloat = 2
        /// Bars → hour numbers.
        static let stripToNumerals = Grid.x1
        /// Hour numbers → verdict line ("with padding").
        static let numeralsToVerdict = Grid.x2
        /// Verdict line → full-width week dots.
        static let verdictToDots = Grid.x2
        static let nameFont: CGFloat = 17
        static let verdictFont: CGFloat = 12
        static let numeralFont: CGFloat = 11
        static let captionFont: CGFloat = 13
        static let iconSize: CGFloat = 18
        static let iconToName = Grid.x2
    }

    // MARK: Card overlay (frame 5 `921:20600`)

    enum Overlay {
        /// Figma backdrop blur 20 (v2) — CSS / SwiftUI radius 10.
        static let blur: CGFloat = 10
        static let copyFont: CGFloat = 15
        static let copyLineSpacing: CGFloat = 4
        static let hintFont: CGFloat = 13
        static let copyToHint = Grid.x2
        static let rimWidth: CGFloat = 1
        /// Raw tints — no Semantic token exists for dark glass (FIGMA note).
        static let lightFill = Color.white.opacity(0.62)
        static let darkFill = Color(red: 22 / 255, green: 24 / 255, blue: 23 / 255).opacity(0.62)
        static let greyWash = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255).opacity(0.2)
        static let lightRim = Color.white
        static let darkRim = Color.white.opacity(0.22)
    }

    // MARK: Detail hero (frames 2 / 4 / 6)

    enum Hero {
        static let ringDiameter = Grid.x4 * 4
        static let ringToCaption = Grid.x1
        static let columnGap = Grid.x4
        static let verdictFont: CGFloat = 17
        static let stripHeight: CGFloat = 5
        static let stripToNumerals = Grid.x1
        static let headerToStrip = Grid.x2
        static let numeralsToCaption = Grid.x1
        static let captionFont: CGFloat = 13
        // Explore
        static let stepDiameter = Grid.x8
        static let pillHeight = Grid.x6
        static let pillRadius = innerRadius
        static let switchToPills = Grid.x2
        static let pillsToBestBar = Grid.x2
        static let bestBarHeight: CGFloat = 3
        static let headerToRows = Grid.x2
        static let rowFont: CGFloat = 13
        /// Text 16 + 2 × 8 band inset: the rows sit at an even 32 pitch.
        static let rowHeight = Grid.x8
        static let bandHorizontalInset = Grid.x3
        static let valueColumn: CGFloat = 96
        static let rowsToBack = Grid.x2
        static let backHeight: CGFloat = 36
        static let backGlyphToText = Grid.x2
    }

    // MARK: Report / Explore switch (owner rule: r12 thumb in r16, 4 inset)

    enum Switch {
        static let inset = Grid.x1
        static let thumbWidth: CGFloat = 36
        static let thumbHeight = Grid.x6
        static let thumbRadius = Grid.x3
        static let radius = thumbRadius + inset
        static var width: CGFloat { thumbWidth * 2 + inset * 2 }
        static var height: CGFloat { thumbHeight + inset * 2 }
        static let glyphSize: CGFloat = 14
    }

    // MARK: Hours-over row (frames 3 / 3b)

    enum HoursOver {
        static let glyphSize: CGFloat = 28
        static let glyphToText = Grid.x3
        static let titleFont: CGFloat = 15
        static let subtitleFont: CGFloat = 13
        static let titleToSubtitle = Grid.x1
        static let pressedBorder: CGFloat = 2
        static let pressDuration: Double = 0.2
        static let slideDuration: Double = 0.3
    }

    // MARK: Coming days (frame 7 `921:21142`)

    enum ComingDays {
        static let titleFont: CGFloat = 11
        static let titleToRows = Grid.x2
        static let rowHeight = Grid.x8
        static let dotSize = Grid.x2
        static let dotToName = Grid.x2
        static let nameFont: CGFloat = 14
        static let nameColumn = Grid.x12
        static let lineFont: CGFloat = 11
        static let averageFont: CGFloat = 11
    }
}
