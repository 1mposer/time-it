import SwiftUI

/// Activity Detail v3 — TODAY ONLY (Figma `456:358` / `464:2348`, owner-
/// approved 2026-09-30). Top to bottom: the hero (day-score ring + rating
/// word + hour stepper over a Range-scoped hour strip), three square metric
/// cards two per row reading the SELECTED hour, then the Edit range / Edit
/// metrics list.
///
/// The week rows and the hour × metric grid are **gone** (today-only ruling);
/// `DayBarPaint` / `RangeAxis` survive as pure types with their own tests —
/// this view simply no longer draws week bars.
///
/// The hero ring shows the DAY score (`days[0].score` from the wire), not a
/// per-hour score: the two linked frames hold 86/Perfect fixed while the
/// stepper moves 6am → 7am and the metric values change.
struct ActivityDetailView: View {
    /// The rating captured at navigation time — a fallback; the body
    /// re-resolves from the live forecast so a refetch updates in place.
    let activity: ActivityRating
    @ObservedObject var viewModel: DashboardViewModel
    /// Metric names and chip icons resolve through the catalog seam.
    var catalog: MetricCatalogProviding = StaticMetricCatalog()
    /// Wind-speed display unit (#26).
    var windUnit: WindSpeedUnit = .kmh

    /// The selected global `hours[]` index; nil until the forecast resolves.
    @State private var selectedIndex: Int?
    /// Drives the snap-back tap's click feedback.
    @State private var stripPressed = false
    /// The open edit door: which Activity and which wizard tab it lands on.
    @State private var editing: EditRequest?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct EditRequest: Identifiable {
        let activity: AuthoredActivity
        let step: EditorStep
        var id: String { activity.id }
    }

    private var deriver: TimeDeriver? { viewModel.timeDeriver }
    private var current: ActivityRating { viewModel.rating(forActivityId: activity.activityId) ?? activity }
    private var authored: AuthoredActivity? { viewModel.authoredActivity(forActivityId: activity.activityId) }
    /// Day 0 read RAW — a rating-null day still carries its score.
    private var today: Day? { viewModel.rawDay(for: current, dayIndex: 0) }

    /// Today's Range hours as global indices.
    private var rangeHours: Range<Int>? {
        authored.flatMap { viewModel.rangeHourIndices(for: $0, dayIndex: 0) }
    }

    /// Every hour the stepper may walk today.
    private var walkable: Range<Int>? {
        authored.flatMap { viewModel.walkableHourRange(for: $0, dayIndex: 0) }
    }

    /// The pure selection model; nil until a forecast exists.
    private var stepper: HourStepper? {
        guard let walkable, !walkable.isEmpty else { return nil }
        let selected = selectedIndex
            ?? HourStepper.initialSelection(walkable: walkable, rangeHours: rangeHours)
        return HourStepper(walkable: walkable, rangeHours: rangeHours, selected: selected)
    }

    private var selectedHour: HourlyWeather? {
        guard let stepper, let hours = viewModel.forecast?.hours,
              hours.indices.contains(stepper.selected) else { return nil }
        return hours[stepper.selected]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                heroCard
                metricGrid
                editCard
            }
            .padding(14)
        }
        .background(Theme.appBackground)
        .navigationTitle(current.label)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { request in
            NavigationStack {
                ActivityEditorView(existing: request.activity,
                                   isNew: false,
                                   initialStep: request.step,
                                   windUnit: windUnit,
                                   onSave: { viewModel.store.update($0) })
            }
        }
    }

    // MARK: Hero — ring + rating word + hour stepper over the Range strip

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                ScoreRingView(score: today?.score,
                              tint: Theme.ratingTint(today?.rating),
                              style: .hero)
                Text(today?.ratingDisplay ?? "No Window")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ratingTint(today?.rating))
                    .fixedSize()
            }
            .frame(width: 64)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("detail.score")
            .accessibilityLabel(scoreAccessibilityLabel)

            VStack(spacing: 0) {
                stepperRow
                Spacer(minLength: 12)
                hourStrip
            }
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
    }

    private var scoreAccessibilityLabel: String {
        let verdict = today?.ratingDisplay ?? "No Window"
        guard let score = today?.score else { return "\(verdict), no score" }
        return "\(verdict), score \(score) out of 100"
    }

    /// `− 6am +`. Both buttons carry a 44pt tap target around a 32pt visual
    /// (the beta pill's `contentShape` pattern); `−` dims at the walkable
    /// lower bound, `+` at the upper.
    private var stepperRow: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus",
                       enabled: stepper?.canStepBack ?? false,
                       identifier: "detail.stepBack") { step(by: -1) }
            Spacer(minLength: 0)
            Text(selectedHourLabel)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Theme.primaryText)
                .accessibilityIdentifier("detail.selectedHour")
            Spacer(minLength: 0)
            stepButton(systemName: "plus",
                       enabled: stepper?.canStepForward ?? false,
                       identifier: "detail.stepForward") { step(by: 1) }
        }
        .frame(height: 44)
    }

    private var selectedHourLabel: String {
        guard let stepper, let deriver else { return "—" }
        return deriver.hourLabel(at: stepper.selected)
    }

    private func stepButton(systemName: String,
                            enabled: Bool,
                            identifier: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentInteractive)
                .frame(width: 32, height: 32)
                .background(Theme.appBackground, in: Circle())
                .opacity(enabled ? 1 : 0.35)
                // The LAYOUT frame stays ≥44pt (HIG tap target) around the
                // 32pt visual circle — the beta pill's pattern.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(systemName == "minus" ? "Previous hour" : "Next hour")
    }

    private func step(by delta: Int) {
        guard var stepper else { return }
        if delta < 0 { stepper.stepBack() } else { stepper.stepForward() }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            selectedIndex = stepper.selected
        }
    }

    /// The Range-scoped hour strip: one 24pt pill per Range hour, the
    /// selected one at full opacity and the rest at 35%.
    ///
    /// Outside the Range (the owner's 2026-09-30 stepper ruling, refined
    /// 2026-10-01) the pills keep their weather colours but none is
    /// highlighted — the hour you were on simply stops shining — and the
    /// strip becomes the way back: tapping it snaps the selection to the
    /// nearest Range end, with a click-feedback scale. Values stay uncoloured
    /// out there (nothing is judged).
    @ViewBuilder
    private var hourStrip: some View {
        if let stepper, let rangeHours, !rangeHours.isEmpty, let authored {
            let inRange = stepper.isInRange
            HStack(spacing: 3) {
                ForEach(Array(rangeHours), id: \.self) { index in
                    pill(at: index, authored: authored, selected: index == stepper.selected, colored: inRange)
                }
            }
            .frame(height: 24)
            .scaleEffect(stripPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: stripPressed)
            // The strip is the way back into the Range, so it needs a 44pt
            // target around its 24pt visual — the ±padding pair is the beta
            // pill's pattern: it grows the hit area without growing the card.
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { snapBack() }
            .padding(.vertical, -10)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("detail.hourStrip")
            .accessibilityLabel(inRange ? "Hours in your range"
                                        : "Outside your range. Activate to return to the range.")
            .accessibilityAddTraits(inRange ? [] : .isButton)
        } else {
            Color.clear.frame(height: 24)
        }
    }

    private func pill(at index: Int,
                      authored: AuthoredActivity,
                      selected: Bool,
                      colored: Bool) -> some View {
        let tier = viewModel.forecast.flatMap { forecast -> HourTier? in
            guard forecast.hours.indices.contains(index) else { return nil }
            return HourQuality.tier(for: forecast.hours[index], thresholds: authored.thresholds)
        }
        let fill = tier.map(Theme.tierColor) ?? Theme.timelineTrack
        return RoundedRectangle(cornerRadius: 6)
            .fill(fill)
            .frame(maxWidth: .infinity)
            .overlay(
                Text(RangeStripAxis.numeral(viewModel.localHour(at: index) ?? 0))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white)
            )
            .opacity(selected && colored ? 1 : 0.35)
    }

    private func snapBack() {
        guard var stepper, stepper.snapBackTarget != nil else { return }
        stripPressed = true
        stepper.snapBack()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            selectedIndex = stepper.selected
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { stripPressed = false }
    }

    // MARK: The three metric cards — two per row, the selected hour's values

    /// ONE card per display metric, in the Activity's own order. The frames
    /// drew a three-metric Activity and never ruled on more — and every
    /// thresholded metric needs a surface somewhere (the v2 card dropped the
    /// chips), so a fourth metric gets a fourth card rather than vanishing.
    private var metricGrid: some View {
        let metrics = current.displayMetrics
        let inRange = stepper?.isInRange ?? false
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 13),
                                   GridItem(.flexible(), spacing: 13)],
                         spacing: 12) {
            ForEach(metrics, id: \.self) { metric in
                MetricCardView(metric: metric,
                               hour: selectedHour,
                               threshold: authored?.thresholds[metric],
                               verdict: verdict(for: metric, inRange: inRange),
                               catalog: catalog,
                               windUnit: windUnit)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    /// Out of Range nothing is judged, so the value renders uncoloured.
    private func verdict(for metric: String, inRange: Bool) -> HourTier? {
        guard inRange, let hour = selectedHour else { return nil }
        return HourQuality.metricTier(for: hour,
                                      metric: metric,
                                      threshold: authored?.thresholds[metric])
    }

    // MARK: Edit range / Edit metrics (kept — the today-only ruling cut only
    // the week rows and the hour grid)

    private var editCard: some View {
        VStack(spacing: 0) {
            editRow("Edit range", identifier: "detail.editRange") {
                if let authored { editing = EditRequest(activity: authored, step: .range) }
            }
            Theme.divider
                .frame(height: 0.5)
                .padding(.leading, 13.5)
            editRow("Edit metrics", identifier: "detail.editMetrics") {
                if let authored { editing = EditRequest(activity: authored, step: .metrics) }
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .disabled(authored == nil)
    }

    private func editRow(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accentInteractive)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 13.5)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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

/// Four thresholded metrics → four cards (the grid is not capped at the
/// frames' three). `PreviewFixtures.cycling` carries temp/wind/rain/uV.
#Preview("Cycling (4 metrics)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[0],
                           viewModel: viewModel)
    }
    .task { await viewModel.loadForecast() }
}

#Preview("Running") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        // activities[2] — the fixture list is cycling / fishingLite / running.
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[2],
                           viewModel: viewModel)
    }
    .task { await viewModel.loadForecast() }
}
#endif
