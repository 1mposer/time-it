import SwiftUI

/// Dashboard card v2 — "Score ring" (Figma `458:394`, owner-approved
/// 2026-09-30). Wordless beyond the name, the numerals and the colour: a 48pt
/// score ring with its "Score" caption, the activity name, an hours-only blue
/// Range chip, and a Range-SCOPED hour strip (one segment per Range hour,
/// tinted by that hour's tier) under boundary numerals.
///
/// The one card: the dashboard draws it, and the wizard's Review reveal draws
/// the same view for the new Activity (owner ruling 2026-11-11 — an exact
/// replica, not a look-alike). The chip is hours-only — "6 – 10am".
struct ScoreRingCardView: View {
    let activity: ActivityRating
    /// The day bucket the card shows — read RAW from `days[]`, never through
    /// a has-window filter: a rating-null day still carries a real low score
    /// (the frame's red 31 ring), and the ring is keyed on `score`, the strip
    /// and tint on `rating`.
    let day: Day?
    /// Explicit icon from the authored Activity.
    var iconSymbol: String?
    /// The authored Range as hours-only chip copy ("6 – 10am"); nil hides it.
    var rangeChipLabel: String?
    /// One strip segment per hour of the FULL authored Range (owner ruling
    /// 2026-11-04): a tier colours it; nil is a gone / no-data hour, drawn as
    /// the grey track. Empty renders the bare track.
    var tiers: [HourTier?] = []
    /// Local hour of the strip's first segment — the boundary numerals count
    /// up from here.
    var stripStartLocalHour: Int?
    /// The week-dot row (spec 05, Figma `517:73` on the ring card `458:394`):
    /// seven days in forecast order, ring on today.
    var weekDots: [WeekDot] = []
    /// The card chevron's state — false = exactly the pre-dots card.
    var showsWeekDots: Bool = false
    /// A data dot's tap (note 16): the dashboard opens the detail on that
    /// day. nil keeps the dots inert (the wizard's Review reveal).
    var onDotTap: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Accessibility sizes put the chip under the name (no squeeze).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The name → strip → numerals block's floor: 65 at the default text
    /// size (the frame's collapsed card), its own height once the scaled
    /// text outgrows it (Dynamic Type, owner ruling 8 — no fixed column).
    static let stripBlockFloor: CGFloat = 65

    private var dotsVisible: Bool { showsWeekDots && !weekDots.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ringColumn
            detailColumn
        }
        .padding(EdgeInsets(top: 11.5, leading: 13.5, bottom: 11.5, trailing: 14.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .cardLift(cornerRadius: 16, light: .rest)
        // .contain keeps the name/chip addressable (the dormant-card
        // pattern); the ring owns its own spoken summary below.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoreCard.\(activity.activityId)")
    }

    // MARK: ring + caption

    private var ringColumn: some View {
        VStack(spacing: 4) {
            ScoreRingView(score: day?.score,
                          tint: Theme.ratingTint(day?.rating),
                          style: .card)
            Text("Score")
                .scaledFont(size: 11, weight: .medium)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .fixedSize()
        }
        // The ring is fixed at 48 (ruling 9a); the caption is a word and
        // grows, so the column is a floor, not a width.
        .frame(minWidth: 48)
        // VoiceOver keeps the words the visual drops — verdict and score.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("score.\(activity.activityId)")
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: name + chip + Range-scoped strip

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                Spacer(minLength: 10)
                // The strip bars never scale (ruling 9a).
                hourStrip
                    .frame(height: 10)
                StripAxisNumerals(tiers: tiers, stripStartLocalHour: stripStartLocalHour)
                    // The numerals scale as text up to xxxLarge, then clamp
                    // (ruling 9a: the strip's numerals may clamp) so they
                    // never overprint each other on the fixed strip.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.top, 4)
            }
            .minHeightFloor(Self.stripBlockFloor)
            // The fold's mask: this wrapper's height springs 42 ↔ 0 with the
            // row, and `.clipped()` hides the row while it slides up under
            // the numerals (owner report 2026-11-05: the chevron de-reveals
            // the row, the reverse of revealing it). The row's 8pt gap rides
            // inside, so nothing at rest is cut.
            VStack(spacing: 0) {
                if dotsVisible {
                    // Frame `458:394`: axis bottom → dots top = 8pt; the row
                    // spans the strip's x and width; 34pt tall (12 label + 4 +
                    // 18 slot). Removed — not hidden — when collapsed, so the
                    // collapsed card is exactly the pre-dots card.
                    WeekDotsView(dots: weekDots,
                                 ringedDayIndex: 0,
                                 onTap: onDotTap,
                                 identifierPrefix: "weekDots.\(activity.activityId)")
                        .padding(.top, 8)
                        .transition(.unfold(reduceMotion: reduceMotion))
                }
            }
            .clipped()
        }
        // 65 = name row → strip → numerals at the default text size; +42
        // (8 gap + 34 row) with dots — the frame's 132 vs 90 delta. Both
        // are intrinsic now: the content's height at any text size.
        .animation(Theme.Motion.reveal(reduceMotion: reduceMotion), value: dotsVisible)
    }

    /// The name and the chip on one line; at accessibility sizes the chip
    /// drops under the name and the name wraps (HIG: stack, don't truncate).
    @ViewBuilder
    private var topRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    icon
                    title
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.trailing, Self.chevronClearance)
                chip
            }
        } else {
            HStack(spacing: 8) {
                icon
                title
                    // One line at the default size and below (the frame);
                    // a larger name wraps rather than truncates.
                    .lineLimit(dynamicTypeSize > .large ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                chip
                Spacer(minLength: 0)
            }
            .padding(.trailing, Self.chevronClearance)
        }
    }

    /// Clears the chevron the dashboard overlays on the card (a 34pt
    /// button ending 4.5pt in from the card edge: 38.5 − the card's 14.5
    /// trailing inset). The card gear is gone (owner ruling 2026-10-06 #2).
    private static let chevronClearance: CGFloat = 24

    private var icon: some View {
        ActivityIconView(identifier: iconSymbol ?? Self.iconName(for: activity), size: 18)
            .foregroundStyle(Theme.primaryText.opacity(0.75))
            .accessibilityHidden(true)
    }

    private var title: some View {
        Text(activity.label)
            .scaledFont(size: 15, weight: .medium)
            .tracking(-0.1)
            .foregroundStyle(Theme.primaryText)
    }

    /// Hours only — the "Range · " prefix is dropped on the v2 card by
    /// owner ruling (FIGMA.md §11). One line that shrinks before it ever
    /// truncates.
    @ViewBuilder
    private var chip: some View {
        if let rangeChipLabel {
            Text(rangeChipLabel)
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Theme.accentBrand)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.accentTint, in: Capsule())
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                .accessibilityIdentifier("rangeChip.\(activity.activityId)")
        }
    }

    /// One rounded segment per Range hour, 2pt apart — the frame's strip.
    @ViewBuilder
    private var hourStrip: some View {
        if tiers.isEmpty {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.timelineTrack)
        } else {
            HStack(spacing: 2) {
                ForEach(Array(tiers.enumerated()), id: \.offset) { _, tier in
                    RoundedRectangle(cornerRadius: 3)
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

    private var accessibilitySummary: String {
        let verdict = day?.ratingDisplay ?? "No Window"
        guard let score = day?.score else { return "\(verdict), no score" }
        return "\(verdict), score \(score) out of 100"
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
    @ScaledMetric(relativeTo: .caption) private var slotHeight: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var halfWidth: CGFloat = 7

    var body: some View {
        if let stripStartLocalHour, !tiers.isEmpty {
            let labels = RangeStripAxis.labels(startLocalHour: stripStartLocalHour,
                                               hourCount: tiers.count)
            GeometryReader { geo in
                ForEach(labels, id: \.boundary) { label in
                    let fraction = CGFloat(label.boundary) / CGFloat(tiers.count)
                    Text(label.text)
                        .scaledFont(size: 12)
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
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16))
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
                          rangeChipLabel: RangeText.chipLabel(WindowSpec(startHour: 6, endHour: 10)),
                          tiers: [nil, .green, .green, .green],
                          stripStartLocalHour: 6)
        ScoreRingCardView(activity: forecast.activities[2],
                          day: Day(dayIndex: 0, rating: nil, score: 31),
                          iconSymbol: "figure.run",
                          rangeChipLabel: RangeText.chipLabel(WindowSpec(startHour: 6, endHour: 9)),
                          tiers: [.red, .red, .red],
                          stripStartLocalHour: 6)
        ScoreRingCardView(activity: forecast.activities[0],
                          day: Day(dayIndex: 0, rating: nil),
                          iconSymbol: "figure.outdoor.cycle",
                          rangeChipLabel: "6 – 10am")
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
                          rangeChipLabel: RangeText.chipLabel(WindowSpec(startHour: 6, endHour: 10)),
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
                          rangeChipLabel: RangeText.chipLabel(WindowSpec(startHour: 6, endHour: 10)),
                          tiers: [nil, .green, .green, .green],
                          stripStartLocalHour: 6)
        ScoreRingCardView(activity: forecast.activities[2],
                          day: Day(dayIndex: 0, rating: nil, score: 31),
                          iconSymbol: "figure.run",
                          rangeChipLabel: RangeText.chipLabel(WindowSpec(startHour: 6, endHour: 9)),
                          tiers: [.red, .red, .red],
                          stripStartLocalHour: 6)
    }
    .padding(14)
    .background(Theme.appBackground)
    .preferredColorScheme(.dark)
}
#endif
