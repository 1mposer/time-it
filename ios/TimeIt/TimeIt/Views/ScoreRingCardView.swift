import SwiftUI

/// Dashboard card — lane RETHINK (Figma Mess around "Final - Opus v2"
/// `921:19890`, owner-approved 2026-11-16). Ring column (the 48pt day-score
/// ring tinted by its SCORE band + the "Average" / "Tomorrow" caption) | text
/// column: name row → the Range-scoped hour strip → the hour integers → the
/// verdict line "7 – 10am · Perfect" in the verdict's tint ("No good time"
/// in red on a null day) — then the week dots across the full card width.
/// No Range pill, no "Best hours" words, no own-hours line (ruling 04 a).
/// Every value lives in `RethinkLayout.Card`.
///
/// The one card: the dashboard draws it, and the wizard's Review reveal draws
/// the same view for the new Activity (owner ruling 2026-11-11 — an exact
/// replica, not a look-alike).
struct ScoreRingCardView: View {
    let activity: ActivityRating
    /// The day bucket the card shows (today, or tomorrow once today's hours
    /// are over) — read RAW from `days[]`: a rating-null day still carries
    /// its score, and the ring is keyed on `score`, the line on `rating`.
    let day: Day?
    /// Explicit icon from the authored Activity.
    var iconSymbol: String?
    /// "7 – 10am · Perfect" / "No good time"; nil hides the line (no
    /// forecast yet — the Review reveal before its reply).
    var verdictLine: VerdictLine?
    /// The ring's caption: "Average" (the day score's name, ruling 03 a) or
    /// "Tomorrow" when the card shows tomorrow (02 b).
    var caption: String = "Average"
    /// One strip segment per hour of the FULL authored Range (owner ruling
    /// 2026-11-04): a tier colours it; nil is a gone / no-data hour, drawn as
    /// the grey track. Empty renders the bare track.
    var tiers: [HourTier?] = []
    /// Local hour of the strip's first segment — the integers count up from it.
    var stripStartLocalHour: Int?
    /// The week-dot row: seven days in forecast order.
    var weekDots: [WeekDot] = []
    /// The card chevron's state — false = no dots row.
    var showsWeekDots: Bool = false
    /// The dot that carries the ring (the shown day).
    var ringedDayIndex: Int = 0
    /// Today's dot, greyed once its hours are over.
    var dimmedDayIndex: Int? = nil
    /// A data dot's tap: the dashboard opens the detail on that day. nil
    /// keeps the dots inert (the wizard's Review reveal).
    var onDotTap: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private typealias Layout = RethinkLayout.Card

    /// The caption's largest size — a label never outranks the data.
    static let captionMaxSize: CGFloat = 14

    private var dotsVisible: Bool { showsWeekDots && !weekDots.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Layout.columnGap) {
                ringColumn
                textColumn
            }
            // The fold's mask: the row slides up under the text column when
            // the chevron hides it; `.clipped()` hides it on the way.
            VStack(spacing: 0) {
                if dotsVisible {
                    WeekDotsView(dots: weekDots,
                                 ringedDayIndex: ringedDayIndex,
                                 dimmedDayIndex: dimmedDayIndex,
                                 onTap: onDotTap,
                                 identifierPrefix: "weekDots.\(activity.activityId)")
                        .padding(.top, Layout.verdictToDots)
                        .transition(.unfold(reduceMotion: reduceMotion))
                }
            }
            .clipped()
        }
        .animation(Theme.Motion.reveal(reduceMotion: reduceMotion), value: dotsVisible)
        .padding(RethinkLayout.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RethinkLayout.shape())
        .cardLift(cornerRadius: RethinkLayout.outerRadius, light: .rest)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoreCard.\(activity.activityId)")
    }

    // MARK: ring + caption

    private var ringColumn: some View {
        VStack(spacing: Layout.ringToCaption) {
            ScoreRingView(score: day?.score,
                          tint: Theme.scoreBandTint(day?.score),
                          style: .card)
            Text(caption)
                .scaledFont(size: Layout.captionFont, weight: .semibold, maxSize: Self.captionMaxSize)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("ringCaption.\(activity.activityId)")
        }
        // A floor, not a width: the caption grows with the text size.
        .frame(minWidth: Layout.ringColumnWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("score.\(activity.activityId)")
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: name → strip → integers → verdict line

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameRow
            hourStrip
                .frame(height: Layout.stripHeight)
                .padding(.top, Layout.nameToStrip)
            StripAxisNumerals(tiers: tiers, stripStartLocalHour: stripStartLocalHour)
                // The integers scale as text up to xxxLarge, then clamp so
                // they never overprint each other on the fixed strip.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.top, Layout.stripToNumerals)
            if let verdictLine {
                Text(verdictLine.text)
                    .scaledFont(size: Layout.verdictFont, weight: .semibold)
                    .foregroundStyle(verdictLine.tint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.numeralsToVerdict)
                    .accessibilityIdentifier("verdictLine.\(activity.activityId)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Icon in a fixed slot, the name (wraps rather than truncates at large
    /// sizes — HIG: stack, don't truncate), clear of the chevron.
    private var nameRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.iconToName) {
            icon
            Text(activity.label)
                .scaledFont(size: Layout.nameFont, weight: .semibold)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(dynamicTypeSize > .large ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.trailing, Self.chevronClearance)
    }

    /// Clears the chevron the dashboard overlays on the card.
    static let chevronClearance: CGFloat = RethinkLayout.Grid.x6

    private var icon: some View {
        ActivityIconView(identifier: iconSymbol ?? Self.iconName(for: activity), size: Layout.iconSize)
            .foregroundStyle(Theme.primaryText)
            .accessibilityHidden(true)
    }

    /// One rounded segment per Range hour, 2pt apart — the frame's strip.
    @ViewBuilder
    private var hourStrip: some View {
        let segment = RoundedRectangle(cornerRadius: Layout.stripHeight / 2, style: .continuous)
        if tiers.isEmpty {
            segment.fill(Theme.timelineTrack)
        } else {
            HStack(spacing: Layout.stripSegmentGap) {
                ForEach(Array(tiers.enumerated()), id: \.offset) { _, tier in
                    segment
                        .fill(tier.map(Theme.tierColor) ?? Theme.timelineTrack)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Legacy icon fallback by activity id; unlisted glyphs get the
    /// questionmark.circle guardrail.
    static func iconName(for activity: ActivityRating) -> String {
        let key = activity.activityId.lowercased()
        if key.contains("cycling") { return "figure.outdoor.cycle" }
        if key.contains("fishing") { return "figure.fishing" }
        return "questionmark.circle"
    }

    /// "Tomorrow, Perfect 6 – 9am, average 91 out of 100".
    private var accessibilitySummary: String {
        let verdict = verdictLine?.text ?? VerdictLine.noGoodTime
        guard let score = day?.score else { return "\(caption), \(verdict), no average" }
        return "\(caption) \(score) out of 100, \(verdict)"
    }
}

/// The strip's boundary numerals, positioned on the segment boundaries: the
/// first left-aligned, the last right-aligned, the rest centred. Its own view
/// so its scaled metrics read the clamped text size it is given.
private struct StripAxisNumerals: View {
    let tiers: [HourTier?]
    let stripStartLocalHour: Int?

    /// The axis slot (14 at the default size) and the half-width estimate
    /// that anchors the end numerals, both scaling with the caption text.
    @ScaledMetric(relativeTo: .caption) private var slotHeight: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var halfWidth: CGFloat = 7

    var body: some View {
        if let stripStartLocalHour, !tiers.isEmpty {
            GeometryReader { geo in
                // Thinned to what the strip's width holds at this text size
                // (note 36: "9 10" printed as "910"); the widest numeral is
                // two digits, about two half-widths.
                let labels = RangeStripAxis.labels(
                    startLocalHour: stripStartLocalHour,
                    hourCount: tiers.count,
                    maxLabels: RangeStripAxis.maxLabels(fittingWidth: geo.size.width,
                                                        labelWidth: 2 * halfWidth))
                ForEach(labels, id: \.boundary) { label in
                    let fraction = CGFloat(label.boundary) / CGFloat(tiers.count)
                    Text(label.text)
                        .scaledFont(size: RethinkLayout.Card.numeralFont, weight: .medium)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                        .position(x: geo.size.width * fraction
                                     + anchorOffset(label.boundary, of: tiers.count),
                                  y: slotHeight / 2)
                }
            }
            .frame(height: slotHeight)
        } else {
            // Reserve the axis slot with no numerals (e.g. a passed-Range
            // today: bare track) so the strip's y and the 8pt axis → dots
            // relation hold either way.
            Color.clear.frame(height: slotHeight)
        }
    }

    /// Horizontal nudge so boundary 0 sits flush left, the last flush right,
    /// and the interior ones centre on their boundary. `.position` places the
    /// view's CENTRE, so the offsets are half-width-based and resolved with a
    /// fixed estimate per glyph count (the numerals are 1–2 digits).
    private func anchorOffset(_ boundary: Int, of count: Int) -> CGFloat {
        if boundary == 0 { return halfWidth }
        if boundary == count { return -halfWidth }
        return 0
    }
}

// MARK: - The card's long-press menu (owner ruling 2026-11-11, build 10)

/// The delete copy every delete door shares — the editor's button and
/// dialog words, reused by the card menu and the detail (one wording).
enum ActivityDeletionCopy {
    static let button = "Delete Activity"
    static let title = "Delete this activity?"
    static let confirm = "Delete"
}

/// What the dashboard card's long-press menu does. A nil move closure
/// disables that direction (the first card cannot move up).
struct CardMenuActions {
    var viewDetails: () -> Void
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    /// Asks — the caller shows the confirmation before anything is deleted.
    var delete: () -> Void
}

extension View {
    /// The system context menu on a dashboard card (supersedes the
    /// 2026-10-06 "no long press" ruling): press → lift preview of the card
    /// → View details / Move ▸ Up · Down / Delete. Plain tap is untouched —
    /// it still opens the detail. nil = no menu (the wizard's Review reveal).
    /// The system supplies the press, the haptic at activation, the preview
    /// collapse and VoiceOver's actions.
    func cardContextMenu(_ actions: CardMenuActions?) -> some View {
        modifier(CardContextMenu(actions: actions))
    }
}

private struct CardContextMenu: ViewModifier {
    let actions: CardMenuActions?

    func body(content: Content) -> some View {
        if let actions {
            content
                // The lift preview takes the card's own rounded shape.
                .contentShape(.contextMenuPreview, RethinkLayout.shape())
                .contextMenu {
                    Button(action: actions.viewDetails) {
                        Label("View details", systemImage: "info.circle")
                    }
                    Menu {
                        Button { actions.moveUp?() } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                        .disabled(actions.moveUp == nil)
                        Button { actions.moveDown?() } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                        .disabled(actions.moveDown == nil)
                    } label: {
                        Label("Move", systemImage: "arrow.up.arrow.down")
                    }
                    Divider()
                    Button(role: .destructive, action: actions.delete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("Card v2 — rated + null") {
    let forecast = PreviewFixtures.forecast
    VStack(spacing: 10) {
        ScoreRingCardView(activity: forecast.activities[0],
                          day: Day(dayIndex: 0, rating: .perfect,
                                   startIndex: 2, endIndex: 6, duration: 4, score: 86),
                          iconSymbol: "figure.outdoor.cycle",
                          verdictLine: VerdictLine(window: "7 – 10am", rating: .perfect),
                          tiers: [nil, .green, .green, .green],
                          stripStartLocalHour: 6)
        ScoreRingCardView(activity: forecast.activities[2],
                          day: Day(dayIndex: 0, rating: nil, score: 31),
                          iconSymbol: "figure.run",
                          verdictLine: VerdictLine(window: nil, rating: nil),
                          tiers: [.red, .red, .red],
                          stripStartLocalHour: 6)
        ScoreRingCardView(activity: forecast.activities[0],
                          day: Day(dayIndex: 0, rating: nil),
                          iconSymbol: "figure.outdoor.cycle",
                          verdictLine: VerdictLine(window: nil, rating: nil))
    }
    .padding(14)
    .background(Theme.appBackground)
}

/// Dynamic Type: the card at the accessibility XXL size — the chip under
/// the name, the height intrinsic, the strip and the dots fixed.
#Preview("Card v2 — Accessibility XXL") {
    let forecast = PreviewFixtures.forecast
    VStack(spacing: 10) {
        ScoreRingCardView(activity: forecast.activities[0],
                          day: Day(dayIndex: 0, rating: .perfect,
                                   startIndex: 2, endIndex: 6, duration: 4, score: 86),
                          iconSymbol: "figure.outdoor.cycle",
                          verdictLine: VerdictLine(window: "7 – 10am", rating: .perfect),
                          tiers: [nil, .green, .green, .green],
                          stripStartLocalHour: 6)
    }
    .padding(14)
    .background(Theme.appBackground)
    .environment(\.dynamicTypeSize, .accessibility4)
}

#Preview("Card v2 — dark") {
    let forecast = PreviewFixtures.forecast
    VStack(spacing: 10) {
        ScoreRingCardView(activity: forecast.activities[0],
                          day: Day(dayIndex: 0, rating: .perfect,
                                   startIndex: 2, endIndex: 6, duration: 4, score: 86),
                          iconSymbol: "figure.outdoor.cycle",
                          verdictLine: VerdictLine(window: "7 – 10am", rating: .perfect),
                          tiers: [nil, .green, .green, .green],
                          stripStartLocalHour: 6)
        ScoreRingCardView(activity: forecast.activities[2],
                          day: Day(dayIndex: 0, rating: nil, score: 31),
                          iconSymbol: "figure.run",
                          verdictLine: VerdictLine(window: nil, rating: nil),
                          tiers: [.red, .red, .red],
                          stripStartLocalHour: 6)
    }
    .padding(14)
    .background(Theme.appBackground)
    .preferredColorScheme(.dark)
}
#endif
