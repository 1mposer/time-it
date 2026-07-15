import SwiftUI

/// The 7-day timeline detail: one section per entry in the activity's OWN
/// days[] (7 or 8 — never assumed), each with the day name, rating, window
/// clock times, and the window's hour rows with all displayMetrics chips.
struct ActivityDetailView: View {
    let activity: ActivityRating
    @ObservedObject var viewModel: DashboardViewModel
    /// Wrapped-window activity → night-phrased day headers ("Tonight",
    /// "Tomorrow night") — its dayIndex is the evening's ordinal (ADR-0004).
    var isNocturnal: Bool = false
    /// Metric names and chip icons resolve through the catalog seam (#5b §4).
    var catalog: MetricCatalogProviding = StaticMetricCatalog()

    private var deriver: TimeDeriver? { viewModel.timeDeriver }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(activity.days) { day in
                    daySection(day)
                }
            }
            .padding(14)
        }
        .background(Theme.appBackground)
        .navigationTitle(activity.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func daySection(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(deriver?.dayName(forDayIndex: day.dayIndex, nocturnal: isNocturnal) ?? "Day \(day.dayIndex)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if day.hasWindow, let deriver,
                   let startIndex = day.startIndex, let endIndex = day.endIndex, let duration = day.duration {
                    Text("\(deriver.hourLabel(at: startIndex))–\(deriver.hourLabel(at: endIndex)) · \(duration)h")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(day.ratingDisplay)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ratingColor(day.rating))
            }

            if day.hasWindow {
                ForEach(viewModel.windowHours(for: day)) { hour in
                    hourRow(hour)
                }
            } else {
                Text("No window")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    private func hourRow(_ hour: HourlyWeather) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(deriver?.hourLabel(at: hour.index) ?? "#\(hour.index)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, alignment: .leading)
            // All displayMetrics here, not just the card's first 3.
            ForEach(activity.displayMetrics, id: \.self) { metric in
                chip(for: metric, hour: hour)
            }
            Spacer()
        }
    }

    private func chip(for metric: String, hour: HourlyWeather) -> some View {
        let tier = MetricTier.tier(for: metric, value: hour.numericValue(for: metric))
        let text = hour.formatted(for: metric)
        return HStack(spacing: 3) {
            ActivityIconView(identifier: catalog.iconSymbol(for: metric), size: 10)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .accessibilityLabel("\(catalog.displayName(for: metric)): \(text)")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(tier.textColor)
        .background(tier.backgroundColor, in: Capsule())
    }

    private func ratingColor(_ rating: String?) -> Color {
        switch rating {
        case "perfect": return Theme.perfectGreen
        case "good": return Theme.accentOrange
        default: return Theme.secondaryText
        }
    }
}
