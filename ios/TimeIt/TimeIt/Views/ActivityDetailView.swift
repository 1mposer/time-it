import SwiftUI

/// Activity detail, top to bottom: one setup card (icon + the Range stated
/// once, with the Edit range / Edit metrics doors), the week as aligned
/// range-zoomed gradient rows with the axis once under the stack, and
/// per-hour numbers behind a tap (one day at a time, collapsed by default).
struct ActivityDetailView: View {
    /// The rating captured at navigation time — a fallback; the body
    /// re-resolves from the live forecast so a refetch updates in place.
    let activity: ActivityRating
    @ObservedObject var viewModel: DashboardViewModel
    /// Wrapped-window activity → night-phrased day rows ("Tonight",
    /// "Tomorrow night").
    var isNocturnal: Bool = false
    /// Metric names and chip icons resolve through the catalog seam.
    var catalog: MetricCatalogProviding = StaticMetricCatalog()

    /// The one expanded day; nil = all collapsed (the default).
    @State private var expandedDayIndex: Int?
    @State private var editing: AuthoredActivity?

    private var deriver: TimeDeriver? { viewModel.timeDeriver }
    private var current: ActivityRating { viewModel.rating(forActivityId: activity.activityId) ?? activity }
    private var authored: AuthoredActivity? { viewModel.authoredActivity(forActivityId: activity.activityId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let authored, let window = authored.window {
                    setupCard(authored: authored, window: window)
                }
                weekCard
            }
            .padding(14)
        }
        .background(Theme.appBackground)
        .navigationTitle(current.label)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { activity in
            NavigationStack {
                ActivityEditorView(existing: activity,
                                   isNew: false,
                                   onSave: { viewModel.store.update($0) })
            }
        }
    }

    // MARK: The setup card — Range stated once + both edit doors
    // (merged into one card, prune pass — owner edit 2026-09-01: icon +
    // "6 – 10am daily", then Edit range, then Edit metrics; the threshold
    // summary line and the word "thresholds" are gone).

    private func setupCard(authored: AuthoredActivity, window: WindowSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ActivityIconView(identifier: authored.iconSymbol, size: 16)
                    .foregroundStyle(Theme.primaryText.opacity(0.75))
                    .accessibilityHidden(true)
                Text(RangeText.headerLabel(window))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
            }
            Button("Edit range") { editing = authored }
                .font(.system(size: 14))
                .foregroundStyle(Theme.accentInteractive)
                .accessibilityIdentifier("detail.editRange")
            Button("Edit metrics") { editing = authored }
                .font(.system(size: 14))
                .foregroundStyle(Theme.accentInteractive)
                .accessibilityIdentifier("detail.editMetrics")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: The week — aligned range-zoomed rows, axis once

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(current.days) { day in
                dayRow(day)
            }
            weekAxis
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    private func dayRow(_ day: Day) -> some View {
        let rangeHours = authored.flatMap { viewModel.rangeHours(for: $0, dayIndex: day.dayIndex) } ?? []
        return VStack(alignment: .leading, spacing: 5) {
            Button {
                expandedDayIndex = expandedDayIndex == day.dayIndex ? nil : day.dayIndex
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(deriver?.dayName(forDayIndex: day.dayIndex, nocturnal: isNocturnal) ?? "Day \(day.dayIndex)")
                            .font(.system(size: 15, weight: .medium))
                            .tracking(-0.1)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        if day.hasWindow, let deriver,
                           let startIndex = day.startIndex, let endIndex = day.endIndex {
                            Text(deriver.rangeLabel(startIndex: startIndex, endIndex: endIndex))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    dayBar(day, rangeHours: rangeHours)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail.day.\(day.dayIndex)")
            .accessibilityLabel(rowAccessibilitySummary(day))
            .disabled(rangeHours.isEmpty)

            if expandedDayIndex == day.dayIndex, !rangeHours.isEmpty {
                expandedHours(rangeHours, dayIndex: day.dayIndex)
            }
        }
    }

    /// The range-zoomed bar: the axis IS the Range, so every row shares it.
    /// Red is reserved for bad-with-data — an uncovered Range paints the
    /// plain track; a rating-null day with covered hours is solid red.
    @ViewBuilder
    private func dayBar(_ day: Day, rangeHours: [HourlyWeather]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        let tiers = authored.map { viewModel.rangeTiers(for: $0, dayIndex: day.dayIndex) } ?? []
        Group {
            switch DayBarPaint.decide(rating: day.rating,
                                      tiers: tiers,
                                      coverage: coverageSpan(rangeHours: rangeHours)) {
            case .track:
                shape.fill(Theme.timelineTrack)
            case .solidRed:
                shape.fill(Theme.badRed)
            case .flat:
                shape.fill(day.rating == "perfect" ? Theme.perfectGreen : Theme.accentOrange)
            case .slice(let span, let tiers):
                ZStack(alignment: .leading) {
                    shape.fill(Theme.timelineTrack)
                    GeometryReader { geo in
                        shape
                            .fill(LinearGradient(stops: Theme.sliceStops(for: tiers),
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geo.size.width * (span.upperBound - span.lowerBound), 4))
                            .offset(x: geo.size.width * span.lowerBound)
                    }
                }
            }
        }
        .frame(height: 14)
        .frame(maxWidth: .infinity)
    }

    /// Where the covered range hours sit on the range-zoomed axis — nil when
    /// nothing is covered.
    private func coverageSpan(rangeHours: [HourlyWeather]) -> Range<Double>? {
        guard let window = authored?.window, let deriver else { return nil }
        return RangeAxis.coverageSpan(window: window,
                                      localHours: rangeHours.map { deriver.localHour(at: $0.index) })
    }

    /// The tapped day's hourly chips — range hours only, all displayMetrics.
    /// (.contain groups them without clobbering the chips' own accessibility.)
    private func expandedHours(_ hours: [HourlyWeather], dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(hours) { hour in
                HStack(alignment: .center, spacing: 6) {
                    Text(deriver?.hourLabel(at: hour.index) ?? "#\(hour.index)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 40, alignment: .leading)
                    ForEach(current.displayMetrics, id: \.self) { metric in
                        chip(for: metric, hour: hour)
                    }
                    Spacer()
                }
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.hours.\(dayIndex)")
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
        .padding(.vertical, 2)
        .foregroundStyle(tier.textColor)
        .background(tier.backgroundColor, in: Capsule())
    }

    /// The Range axis, once under the stack: start / midpoint / end.
    @ViewBuilder
    private var weekAxis: some View {
        if let window = authored?.window {
            let labels = RangeText.axisLabels(window)
            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { offset, label in
                    if offset > 0 { Spacer() }
                    Text(label)
                }
            }
            .font(.system(size: 10))
            .tracking(0.1)
            .foregroundStyle(Theme.secondaryText)
        }
    }

    /// VoiceOver keeps rating word + times per row — one dialect with the card.
    private func rowAccessibilitySummary(_ day: Day) -> String {
        let name = deriver?.dayName(forDayIndex: day.dayIndex, nocturnal: isNocturnal) ?? "Day \(day.dayIndex)"
        guard day.hasWindow, let deriver,
              let startIndex = day.startIndex, let endIndex = day.endIndex else {
            return "\(name), no qualifying window"
        }
        return "\(name), \(day.ratingDisplay) window, \(deriver.hourLabel(at: startIndex)) to \(deriver.hourLabel(at: endIndex))"
    }
}

#if DEBUG
#Preview("Cycling (Perfect today)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[0],
                           viewModel: viewModel)
    }
    .task { await viewModel.loadForecast() }
}

#Preview("Stargazing (nocturnal)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[3],
                           viewModel: viewModel,
                           isNocturnal: true)
    }
    .task { await viewModel.loadForecast() }
}
#endif
