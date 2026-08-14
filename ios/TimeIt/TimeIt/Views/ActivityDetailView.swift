import SwiftUI

/// The spec 14 §7 detail skeleton (Figma 111:62 / nocturnal 275:1535), top to
/// bottom: the Range stated once (+ Edit range) · the setup stated once
/// (+ Edit metrics & thresholds) · the week as aligned RANGE-ZOOMED gradient
/// rows (one per entry in the activity's OWN days[] — 7 diurnal, 6 nocturnal,
/// never assumed) with the axis once under the stack · per-hour numbers only
/// behind a tap (progressive disclosure, one day at a time, collapsed by
/// default). The per-hour metric rows screen this replaces is gone.
struct ActivityDetailView: View {
    /// The rating captured at push time — a fallback; the body re-resolves
    /// from the live forecast so an edit-triggered refetch updates in place.
    let activity: ActivityRating
    @ObservedObject var viewModel: DashboardViewModel
    /// Wrapped-window activity → night-phrased day rows ("Tonight",
    /// "Tomorrow night") — dayIndex is the evening's ordinal (ADR-0004).
    var isNocturnal: Bool = false
    /// Metric names and chip icons resolve through the catalog seam (#5b §4).
    var catalog: MetricCatalogProviding = StaticMetricCatalog()

    /// §7.4: the one expanded day; nil = all collapsed (the default).
    @State private var expandedDayIndex: Int?
    @State private var editing: AuthoredActivity?

    private var deriver: TimeDeriver? { viewModel.timeDeriver }
    private var current: ActivityRating { viewModel.rating(forActivityId: activity.activityId) ?? activity }
    private var authored: AuthoredActivity? { viewModel.authoredActivity(forActivityId: activity.activityId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let authored, let window = authored.window {
                    windowHeader(authored: authored, window: window)
                    if let summary = ThresholdSummary.line(for: authored, catalog: catalog) {
                        setupSummary(summary, authored: authored)
                    }
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

    // MARK: §7.1 — the Range stated once

    private func windowHeader(authored: AuthoredActivity, window: WindowSpec) -> some View {
        HStack(spacing: 8) {
            ActivityIconView(identifier: authored.iconSymbol, size: 16)
                .foregroundStyle(Theme.primaryText.opacity(0.75))
                .accessibilityHidden(true)
            Text(RangeText.headerLabel(window))
                .font(.system(size: 14))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Button("Edit range") { editing = authored }
                .font(.system(size: 14))
                .foregroundStyle(Theme.accentInteractive)
                .accessibilityIdentifier("detail.editRange")
        }
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: §7.2 — the setup stated once (thresholds don't vary by hour)

    private func setupSummary(_ summary: String, authored: AuthoredActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("detail.setupSummary")
            Button("Edit metrics & thresholds") { editing = authored }
                .font(.system(size: 14))
                .foregroundStyle(Theme.accentInteractive)
                .accessibilityIdentifier("detail.editMetrics")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: §7.3 — the week: aligned range-zoomed rows, axis once

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
                // §7.4: progressive disclosure, one day at a time.
                expandedDayIndex = expandedDayIndex == day.dayIndex ? nil : day.dayIndex
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(deriver?.dayName(forDayIndex: day.dayIndex, nocturnal: isNocturnal) ?? "Day \(day.dayIndex)")
                            .font(.system(size: 15, weight: .medium))
                            .tracking(-0.1)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        // Best-stretch time; a red day has no stretch (I7) —
                        // the plain day name stands alone.
                        if day.hasWindow, let deriver,
                           let startIndex = day.startIndex, let endIndex = day.endIndex {
                            Text(deriver.rangeLabel(startIndex: startIndex, endIndex: endIndex))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    dayBar(day)
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

    /// The range-zoomed bar: the axis IS the Range, so every row shares it and
    /// the week compares as one vertical scan. Server truth outranks the
    /// mirror (§3): a `rating: null` day is solid red; a rated day blends one
    /// stop per range hour.
    @ViewBuilder
    private func dayBar(_ day: Day) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        Group {
            if day.rating == nil {
                shape.fill(Theme.badRed)
            } else {
                let tiers = authored.map { viewModel.rangeTiers(for: $0, dayIndex: day.dayIndex) } ?? []
                if tiers.isEmpty {
                    // No authored range hours to mirror (lookup miss) — fall
                    // back to the server verdict as a flat fill.
                    shape.fill(day.rating == "perfect" ? Theme.perfectGreen : Theme.accentOrange)
                } else {
                    shape.fill(LinearGradient(stops: TierGradient.stops(for: tiers).map {
                        Gradient.Stop(color: Theme.tierColor($0.tier), location: $0.location)
                    }, startPoint: .leading, endPoint: .trailing))
                }
            }
        }
        .frame(height: 14)
        .frame(maxWidth: .infinity)
    }

    /// §7.4: the tapped day's hourly chips — range hours only, all
    /// displayMetrics (the only surviving home of per-hour numbers).
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
        // .contain: expose the group as a named container without clobbering
        // the chips' own accessibility (see ShowcaseCardView).
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

    /// VoiceOver keeps rating word + times per row (§2's C decision is
    /// visual-only, one dialect with the card).
    private func rowAccessibilitySummary(_ day: Day) -> String {
        let name = deriver?.dayName(forDayIndex: day.dayIndex, nocturnal: isNocturnal) ?? "Day \(day.dayIndex)"
        guard day.hasWindow, let deriver,
              let startIndex = day.startIndex, let endIndex = day.endIndex else {
            return "\(name), no qualifying window"
        }
        return "\(name), \(day.ratingDisplay) window, \(deriver.hourLabel(at: startIndex)) to \(deriver.hourLabel(at: endIndex))"
    }
}
