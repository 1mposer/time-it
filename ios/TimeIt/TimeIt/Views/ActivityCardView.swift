import SwiftUI

/// Dashboard card: summarises day 0 (today/tonight) for one live activity —
/// icon, label, range chip, sublabel, the day-axis bar with the Range's
/// gradient slice, an optional phrase, and the first three metric chips.
/// No rating word — color carries quality; VoiceOver speaks the full summary.
struct ActivityCardView: View {
    let activity: ActivityRating
    /// Day 0 from `DashboardViewModel.cardDay(for:)`; nil means today's Range
    /// has no qualifying window (the all-red state).
    let day: Day?
    let windowStartHour: HourlyWeather?
    let deriver: TimeDeriver?
    let hoursCount: Int
    /// Explicit icon from the authored Activity; nil falls back to the legacy
    /// id heuristic below.
    var iconSymbol: String?
    /// Wrapped-window activity → night-phrased labels.
    var isNocturnal: Bool = false
    /// The authored Range as chip copy ("6 – 10am"); nil hides the chip.
    var rangeChipLabel: String?
    /// Global hours[] indices the Range covers today — where the slice
    /// paints. Nil/empty paints nothing; the gray track alone means no data.
    var sliceRange: Range<Int>?
    /// Per-hour tiers over `sliceRange`.
    var tiers: [HourTier] = []
    /// The phrase slot under the axis; nil hides it.
    var phrase: String?
    /// Metric names and chip icons resolve through the catalog seam.
    var catalog: MetricCatalogProviding = StaticMetricCatalog()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow
            // A rating-null day carries no sublabel — the red slice alone is
            // the verdict (approved frame: Card — Nothing in your range).
            if day != nil {
                Text(sublabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            TimelineBarView(day: day,
                            deriver: deriver,
                            hoursCount: hoursCount,
                            activityId: activity.activityId,
                            sliceRange: sliceRange,
                            tiers: tiers)
            if let phrase {
                Text(phrase)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("phrase.\(activity.activityId)")
            }
            chipRow
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }

    /// The gear is overlaid by DashboardView (above the NavigationLink) so it
    /// stays independently tappable — the trailing padding clears it.
    private var topRow: some View {
        HStack(alignment: .center, spacing: 8) {
            ActivityIconView(identifier: iconSymbol ?? Self.iconName(for: activity), size: 18)
                .foregroundStyle(Theme.primaryText.opacity(0.75))
                .accessibilityHidden(true)
            Text(activity.label)
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.1)
                .foregroundStyle(Theme.primaryText)
            if let rangeChipLabel {
                Text("Range · \(rangeChipLabel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accentInteractive)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.accentInteractive.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Range \(rangeChipLabel)")
                    .accessibilityIdentifier("rangeChip.\(activity.activityId)")
            }
            Spacer()
        }
        .padding(.trailing, 28)
    }

    /// "Today · 6–8pm" / "Tonight · 10pm–2am" — same dialect as the push
    /// copy. A red day is the plain day name.
    private var sublabel: String {
        guard let deriver else { return isNocturnal ? "Tonight" : "Today" }
        return deriver.sublabel(forDayIndex: 0,
                                startIndex: day?.startIndex,
                                endIndex: day?.endIndex,
                                nocturnal: isNocturnal)
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(activity.displayMetrics.prefix(3)), id: \.self) { metric in
                chip(for: metric)
            }
            Spacer()
        }
    }

    private func chip(for metric: String) -> some View {
        let tier = windowStartHour.map { MetricTier.tier(for: metric, value: $0.numericValue(for: metric)) } ?? MetricTier.neutral
        let text = windowStartHour?.formatted(for: metric) ?? catalog.displayName(for: metric)
        return HStack(spacing: 4) {
            ActivityIconView(identifier: catalog.iconSymbol(for: metric), size: 12)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(0.05)
                .accessibilityLabel("\(catalog.displayName(for: metric)): \(text)")
                .accessibilityIdentifier("chip.\(activity.activityId).\(metric)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(tier.textColor)
        .background(tier.backgroundColor, in: Capsule())
    }

    /// Legacy icon fallback by activity id; unlisted glyphs get the
    /// questionmark.circle guardrail.
    static func iconName(for activity: ActivityRating) -> String {
        let key = activity.activityId.lowercased()
        if key.contains("cycling") { return "figure.outdoor.cycle" }
        if key.contains("fishing") { return "figure.fishing" }
        return "questionmark.circle"
    }
}

/// Chip colour tiers — presentation logic, so it lives with the card view.
enum MetricTier: Equatable {
    case green
    case orange
    case red
    /// No data (nil value) or a metric with no tier table.
    case neutral

    static func tier(for metric: String, value: Double?) -> MetricTier {
        guard let value else { return .neutral }
        switch metric {
        case "temp":
            if value >= 38 { return .red }
            if value >= 33 { return .orange }
            return .green
        case "uV":
            if value >= 7 { return .red }
            if value >= 4 { return .orange }
            return .green
        case "windSpeed":
            if value >= 36 { return .red }
            if value >= 21 { return .orange }
            return .green
        case "humidity":
            if value >= 76 { return .red }
            if value >= 61 { return .orange }
            return .green
        case "cloudCover":
            if value >= 61 { return .red }
            if value >= 21 { return .orange }
            return .green
        default:
            return .neutral
        }
    }

    var textColor: Color {
        switch self {
        case .green: return Color(hex: 0x1a7a35)
        case .orange: return Color(hex: 0xb85c00)
        case .red: return Color(hex: 0xc0392b)
        case .neutral: return Color(hex: 0x636366)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .green: return Color(hex: 0x34c759, opacity: 0.12)
        case .orange: return Color(hex: 0xff9500, opacity: 0.12)
        case .red: return Color(hex: 0xff3b30, opacity: 0.12)
        case .neutral: return Color(hex: 0x8e8e93, opacity: 0.12)
        }
    }
}

/// The card's timeline bar: the day's real hour span as the axis, with the
/// Range painted as a per-hour gradient slice. A rating-null day paints
/// solid red; the gray track alone means no data.
struct TimelineBarView: View {
    let day: Day?
    let deriver: TimeDeriver?
    let hoursCount: Int
    let activityId: String
    /// Global hours[] indices the Range covers in the shown day bucket.
    var sliceRange: Range<Int>?
    /// Per-hour tiers over `sliceRange` — one gradient stop per hour.
    var tiers: [HourTier] = []

    /// The shown day's real hour span, widened to cover the day's window and
    /// the range slice — a night-stitched range crosses the calendar day's
    /// end, so without the widening the slice would draw off the track.
    private var axisRange: Range<Int>? {
        guard var span = deriver?.hourRange(forDayIndex: day?.dayIndex ?? 0, hourCount: hoursCount) else {
            return nil
        }
        if let day, day.hasWindow,
           let startIndex = day.startIndex, let endIndex = day.endIndex {
            span = widen(span, toInclude: startIndex..<endIndex)
        }
        if let sliceRange, !sliceRange.isEmpty {
            span = widen(span, toInclude: sliceRange)
        }
        return span
    }

    private func widen(_ span: Range<Int>, toInclude other: Range<Int>) -> Range<Int> {
        let lower = Swift.min(span.lowerBound, Swift.max(other.lowerBound, 0))
        let upper = Swift.max(span.upperBound, Swift.min(other.upperBound, hoursCount))
        return lower < upper ? lower..<upper : span
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.timelineTrack)
                    if let slice = sliceRange, !slice.isEmpty,
                       let range = axisRange, !range.isEmpty {
                        let unit = geo.size.width / CGFloat(range.count)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(sliceStyle)
                            .frame(width: max(unit * CGFloat(slice.count), 4))
                            .offset(x: unit * CGFloat(slice.lowerBound - range.lowerBound))
                    }
                }
            }
            .frame(height: 22)
            axisLabels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("timeline.\(activityId)")
        .accessibilityLabel(accessibilitySummary)
    }

    /// A rating-null day is solid red regardless of the tiers; a rated day
    /// blends one gradient stop per hour.
    private var sliceStyle: AnyShapeStyle {
        guard day?.rating != nil, !tiers.isEmpty else {
            return AnyShapeStyle(Theme.badRed)
        }
        return AnyShapeStyle(LinearGradient(stops: Theme.sliceStops(for: tiers),
                                            startPoint: .leading, endPoint: .trailing))
    }

    /// Two labels only — the axis ends (owner edit 2026-09-01: the interior
    /// labels were clutter).
    @ViewBuilder
    private var axisLabels: some View {
        if let range = axisRange, let deriver, range.count >= 3 {
            HStack {
                Text(deriver.hourLabel(at: range.lowerBound))
                Spacer()
                Text(deriver.hourLabel(at: range.upperBound))
            }
            .font(.system(size: 10))
            .tracking(0.1)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 2)
        }
    }

    /// VoiceOver keeps the full summary — rating word + times — even though
    /// the visual carries no rating word.
    private var accessibilitySummary: String {
        guard let day, day.hasWindow, let deriver,
              let startIndex = day.startIndex, let endIndex = day.endIndex else {
            return "No qualifying window"
        }
        return "\(day.ratingDisplay) window, \(deriver.hourLabel(at: startIndex)) to \(deriver.hourLabel(at: endIndex))"
    }
}

#if DEBUG
#Preview("Perfect + no-window") {
    let forecast = PreviewFixtures.forecast
    let perfect = forecast.activities[0]
    let perfectDay = perfect.days[0]
    let red = forecast.activities[2]
    ScrollView {
        VStack(spacing: 10) {
            ActivityCardView(activity: perfect,
                             day: perfectDay,
                             windowStartHour: perfectDay.startIndex.map { forecast.hours[$0] },
                             deriver: PreviewFixtures.timeDeriver,
                             hoursCount: forecast.hours.count,
                             iconSymbol: "figure.outdoor.cycle",
                             rangeChipLabel: RangeText.chipLabel(WindowSpec(startHour: 6, endHour: 10)),
                             sliceRange: 2..<6,
                             tiers: [.green, .green, .green, .green],
                             phrase: "Perfect all morning.")
            ActivityCardView(activity: red,
                             day: nil,
                             windowStartHour: nil,
                             deriver: PreviewFixtures.timeDeriver,
                             hoursCount: forecast.hours.count,
                             iconSymbol: "figure.run",
                             rangeChipLabel: RangeText.chipLabel(WindowSpec(startHour: 6, endHour: 9)),
                             sliceRange: 2..<5,
                             tiers: [.red, .red, .orange])
        }
        .padding(14)
    }
    .background(Theme.appBackground)
}
#endif
