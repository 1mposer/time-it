import SwiftUI

/// Dashboard card v2 — "Score ring" (Figma `458:394`, owner-approved
/// 2026-09-30). Wordless beyond the name, the numerals and the colour: a 48pt
/// score ring with its "Score" caption, the activity name, an hours-only blue
/// Range chip, and a Range-SCOPED hour strip (one segment per Range hour,
/// tinted by that hour's tier) under boundary numerals.
///
/// What changed from `ActivityCardView` (the main-look card, still used by the
/// wizard's review preview): the ring replaces the sublabel, the strip
/// replaces the 6am–12am day-axis bar, the metric chips move to the detail's
/// metric cards, and the chip is hours-only — "6 – 10am", no "Range · "
/// prefix. The prefix survives on every surface the v2 frames don't cover.
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
    /// Per-hour tiers over the Range hours shown today — one strip segment
    /// each. Empty renders the bare track (no data).
    var tiers: [HourTier] = []
    /// Local hour of the strip's first segment — the boundary numerals count
    /// up from here.
    var stripStartLocalHour: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ringColumn
            detailColumn
        }
        .padding(EdgeInsets(top: 11.5, leading: 13.5, bottom: 11.5, trailing: 14.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(width: 48)
        // VoiceOver keeps the words the visual drops — verdict and score.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("score.\(activity.activityId)")
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: name + chip + Range-scoped strip

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 10)
            hourStrip
                .frame(height: 10)
            axisNumerals
                .padding(.top, 4)
        }
        .frame(height: 65, alignment: .top)
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            ActivityIconView(identifier: iconSymbol ?? ActivityCardView.iconName(for: activity), size: 18)
                .foregroundStyle(Theme.primaryText.opacity(0.75))
                .accessibilityHidden(true)
            Text(activity.label)
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            if let rangeChipLabel {
                // Hours only — the "Range · " prefix is dropped on the v2
                // card by owner ruling (FIGMA.md §11).
                Text(rangeChipLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accentInteractive)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Theme.accentInteractive.opacity(0.12), in: Capsule())
                    .fixedSize()
                    .accessibilityIdentifier("rangeChip.\(activity.activityId)")
            }
            Spacer(minLength: 0)
        }
        // Clears the gear button the dashboard overlays on the card.
        .padding(.trailing, 28)
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
                        .fill(Theme.tierColor(tier))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Boundary numerals, positioned on the segment boundaries: the first
    /// left-aligned, the last right-aligned, the rest centred.
    @ViewBuilder
    private var axisNumerals: some View {
        if let stripStartLocalHour, !tiers.isEmpty {
            let labels = RangeStripAxis.labels(startLocalHour: stripStartLocalHour,
                                               hourCount: tiers.count)
            GeometryReader { geo in
                ForEach(labels, id: \.boundary) { label in
                    let fraction = CGFloat(label.boundary) / CGFloat(tiers.count)
                    Text(label.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                        .position(x: geo.size.width * fraction
                                     + anchorOffset(label.boundary, of: tiers.count),
                                  y: 7)
                }
            }
            .frame(height: 14)
        }
    }

    /// Horizontal nudge so boundary 0 sits flush left, the last flush right,
    /// and the interior ones centre on their boundary. `.position` places the
    /// view's CENTRE, so the offsets are half-width-based and resolved with a
    /// fixed estimate per glyph count (the numerals are 1–2 digits).
    private func anchorOffset(_ boundary: Int, of count: Int) -> CGFloat {
        let halfWidth: CGFloat = 7
        if boundary == 0 { return halfWidth }
        if boundary == count { return -halfWidth }
        return 0
    }

    private var accessibilitySummary: String {
        let verdict = day?.ratingDisplay ?? "No Window"
        guard let score = day?.score else { return "\(verdict), no score" }
        return "\(verdict), score \(score) out of 100"
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
                          tiers: [.orange, .green, .green, .green],
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
#endif
