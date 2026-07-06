import SwiftUI

/// Dashboard card: summarises the SOONEST-ACTIONABLE day for one activity —
/// icon + label, day name, timeline bar, first-3 metric chips.
struct ActivityCardView: View {
    let activity: ActivityRating
    /// The soonest-actionable day from `DashboardViewModel.cardDay(for:)`; nil
    /// means no window anywhere in the activity's days[].
    let day: Day?
    let windowStartHour: HourlyWeather?
    let deriver: TimeDeriver?
    let hoursCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow
            TimelineBarView(day: day, deriver: deriver, hoursCount: hoursCount, activityId: activity.activityId)
            chipRow
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var topRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: Self.iconName(for: activity))
                .font(.system(size: 18))
                .foregroundStyle(Theme.primaryText.opacity(0.75))
                .accessibilityHidden(true) // decorative — the label text follows
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.label)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(Theme.primaryText)
                Text(dayLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            // The card gear (threshold/authoring editor) is a #5b entry point — omitted in #5a.
        }
    }

    /// The card shows the soonest-actionable day, which is not always today —
    /// name it, derived in the response timezone.
    private var dayLabel: String {
        guard let day else { return "No window in the next 7 days" }
        return deriver?.dayName(forDayIndex: day.dayIndex) ?? "Day \(day.dayIndex)"
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
        let text = windowStartHour?.formatted(for: metric) ?? HourlyWeather.label(for: metric)
        return HStack(spacing: 4) {
            Image(systemName: Self.chipIcon(for: metric))
                .font(.system(size: 12))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .tracking(0.05)
                .accessibilityLabel("\(HourlyWeather.label(for: metric)): \(text)")
                .accessibilityIdentifier("chip.\(activity.activityId).\(metric)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(tier.textColor)
        .background(tier.backgroundColor, in: Capsule())
    }

    /// Activity icon. Names come from the SF Symbols manifest in
    /// design-decisions-issue-5.md — never invent or substitute a name;
    /// unlisted glyphs fall back to the questionmark.circle guardrail.
    static func iconName(for activity: ActivityRating) -> String {
        let key = activity.activityId.lowercased()
        if key.contains("cycling") { return "figure.outdoor.cycle" }
        if key.contains("fishing") { return "figure.fishing" }
        return "questionmark.circle"
    }

    /// Metric chip icons — manifest table B.
    static func chipIcon(for metric: String) -> String {
        switch metric {
        case "temp": return "thermometer.medium"
        case "windSpeed": return "wind"
        case "rainFall": return "cloud.rain.fill"
        case "uV": return "sun.max.fill"
        case "cloudCover": return "cloud.fill"
        case "humidity": return "humidity.fill"
        case "visibility": return "eye.fill"
        case "moon": return "moon.stars.fill"
        case "dustAlert": return "sun.dust.fill"
        default: return "questionmark.circle"
        }
    }
}

/// Chip colour tiers (Guidelines.md "Metric chip colour tiers"). Lives with the
/// card view — this is presentation logic, not a shared model.
enum MetricTier: Equatable {
    case green
    case orange
    case red
    /// No data (nil value) or a metric with no tier table (e.g. rainFall, moon).
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

/// The card's 22pt timeline bar. The highlight is positioned from the day's
/// GLOBAL startIndex/duration against the day's REAL hour span in the response
/// timezone — never a hardcoded 6am–midnight axis (a window can fall at any hour).
struct TimelineBarView: View {
    let day: Day?
    let deriver: TimeDeriver?
    let hoursCount: Int
    let activityId: String

    /// The axis span: the shown day's real hours (day 0's span when no window
    /// exists anywhere, so the empty track still reads as "today").
    private var axisRange: Range<Int>? {
        deriver?.hourRange(forDayIndex: day?.dayIndex ?? 0, hourCount: hoursCount)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.timelineTrack)
                    if let day, day.hasWindow,
                       let range = axisRange, !range.isEmpty,
                       let startIndex = day.startIndex, let duration = day.duration {
                        let unit = geo.size.width / CGFloat(range.count)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(fillColor(for: day.rating).opacity(0.85))
                            .frame(width: max(unit * CGFloat(duration), 4))
                            .offset(x: unit * CGFloat(startIndex - range.lowerBound))
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

    @ViewBuilder
    private var axisLabels: some View {
        if let range = axisRange, let deriver, range.count >= 3 {
            HStack {
                Text(deriver.hourLabel(at: range.lowerBound))
                Spacer()
                Text(deriver.hourLabel(at: range.lowerBound + range.count / 3))
                Spacer()
                Text(deriver.hourLabel(at: range.lowerBound + 2 * range.count / 3))
                Spacer()
                Text(deriver.hourLabel(at: range.upperBound))
            }
            .font(.system(size: 10))
            .tracking(0.1)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 2)
        }
    }

    private func fillColor(for rating: String?) -> Color {
        rating == "perfect" ? Theme.perfectGreen : Theme.accentOrange
    }

    private var accessibilitySummary: String {
        guard let day, day.hasWindow, let deriver,
              let startIndex = day.startIndex, let endIndex = day.endIndex else {
            return "No window"
        }
        return "\(day.ratingDisplay) window, \(deriver.hourLabel(at: startIndex)) to \(deriver.hourLabel(at: endIndex))"
    }
}
