import SwiftUI

/// Activity Detail v3 (Figma `456:358` / `464:2348`, owner-approved
/// 2026-09-30; day-jump `508:417`, owner-approved 2026-10-02; hero carousel —
/// depth & polish pass build 8, owner rulings 2026-10-31 / 2026-11-01). Opens
/// on TODAY. Top to bottom: the week-dot row (the day-jump control — ring on
/// the selected day), the hero (day-score ring + rating word + the hour
/// carousel: `−` · a row of tier-coloured hour pills · `+`, with an icon-only
/// return-to-range control under it), square metric cards two per row
/// AVERAGING the chosen hours, then the Edit range / Edit metrics list.
///
/// The hero ring shows the selected DAY's score (`days[selectedDayIndex]
/// .score` from the wire), never the chosen hours' — the ring, the rating
/// word and the day selection do not move with the carousel.
struct ActivityDetailView: View {
    /// The rating captured at navigation time — a fallback; the body
    /// re-resolves from the live forecast so a refetch updates in place.
    let activity: ActivityRating
    @ObservedObject var viewModel: DashboardViewModel
    /// Metric names and chip icons resolve through the catalog seam.
    var catalog: MetricCatalogProviding = StaticMetricCatalog()
    /// Wind-speed display unit (#26).
    var windUnit: WindSpeedUnit = .kmh
    /// The clock the passed-hour grey reads — injectable for previews/tests.
    var now: () -> Date = Date.init

    /// The day the detail shows — opens on today; the week-dot row jumps it
    /// (spec 05 day-jump, frame `508:417`).
    @State private var selectedDayIndex = 0
    /// The carousel once the user has moved it; nil = the opening state
    /// (span on the Range). Reset on a day-jump and a re-based refetch.
    @State private var carouselState: HourCarousel?
    /// The measured width of the pill track between `−` and `+`.
    @State private var trackWidth: CGFloat = 0
    /// Whole-hour steps already applied by the drag in flight.
    @State private var dragSteps = 0
    /// The open edit door: which Activity and which wizard tab it lands on.
    @State private var editing: EditRequest?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pillGap: CGFloat = 3
    private static let rowHeight: CGFloat = 26

    private struct EditRequest: Identifiable {
        let activity: AuthoredActivity
        let step: EditorStep
        var id: String { activity.id }
    }

    private var deriver: TimeDeriver? { viewModel.timeDeriver }
    private var current: ActivityRating { viewModel.rating(forActivityId: activity.activityId) ?? activity }
    private var authored: AuthoredActivity? { viewModel.authoredActivity(forActivityId: activity.activityId) }
    /// The shown day read RAW — a rating-null day still carries its score.
    private var selectedDay: Day? { viewModel.rawDay(for: current, dayIndex: selectedDayIndex) }

    /// The shown day's Range hours as global indices.
    private var rangeHours: Range<Int>? {
        authored.flatMap { viewModel.rangeHourIndices(for: $0, dayIndex: selectedDayIndex) }
    }

    /// Every hour the carousel may show on the shown day.
    private var walkable: Range<Int>? {
        authored.flatMap { viewModel.walkableHourRange(for: $0, dayIndex: selectedDayIndex) }
    }

    /// The pure carousel model; nil until a forecast exists. A stored state
    /// survives only while it still describes the same day and row width.
    private var carousel: HourCarousel? {
        guard let walkable, !walkable.isEmpty else { return nil }
        let slots = HourCarousel.visibleSlotCount(rangeLength: rangeHours?.count ?? 1,
                                                  availableWidth: Double(trackWidth))
        let fresh = HourCarousel(walkable: walkable, rangeHours: rangeHours, visibleSlots: slots)
        if let carouselState,
           carouselState.walkable == fresh.walkable,
           carouselState.rangeHours == fresh.rangeHours,
           carouselState.visibleSlots == fresh.visibleSlots {
            return carouselState
        }
        return fresh
    }

    /// The hours the metric cards read — the carousel's chosen span. A later
    /// Calculate button would freeze this until pressed; today it is live.
    private var displayedHours: [HourlyWeather] {
        guard let carousel, let hours = viewModel.forecast?.hours else { return [] }
        return carousel.span.filter(hours.indices.contains).map { hours[$0] }
    }

    /// The chosen hours folded into one reading (`HourAggregate`).
    private var displayedHour: HourlyWeather? { HourAggregate.aggregate(displayedHours) }

    var body: some View {
        ScrollView {
            // Frame `508:417`: the dot row under the nav at full content
            // width, a 10pt gap to the hero (matched exactly — the rest of the
            // stack keeps its 12pt rhythm).
            VStack(alignment: .leading, spacing: 10) {
                if !weekDots.isEmpty {
                    WeekDotsView(dots: weekDots,
                                 ringedDayIndex: selectedDayIndex,
                                 onTap: jump(to:),
                                 identifierPrefix: "detail.weekDot")
                }
                VStack(alignment: .leading, spacing: 12) {
                    heroCard
                    metricGrid
                    editCard
                }
            }
            // Frame `508:417`: the dots sit 12pt under the nav bar.
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background(Theme.appBackground)
        // Re-base guard: a refetch across a day rollover shifts what each
        // dayIndex / hours[] index means, so a stale selection would point at
        // a shifted or absent day — reset to today, carousel back on the Range.
        .onChange(of: viewModel.forecast?.forecastStart) { _, _ in
            selectedDayIndex = 0
            carouselState = nil
        }
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

    // MARK: Week dots — the day-jump control

    private var weekDots: [WeekDot] {
        deriver.map {
            WeekDots.dots(for: current, deriver: $0,
                          nocturnal: viewModel.isNocturnal(activityId: activity.activityId))
        } ?? []
    }

    /// Shows another day: the ring moves, the hero + carousel + metric cards
    /// re-read for it, and the carousel re-opens on its Range.
    /// A day absent from `days[]` or with no data is not a target, and
    /// tapping the already-ringed dot is a no-op (it must not reset the
    /// carousel).
    private func jump(to day: Int) {
        guard day != selectedDayIndex,
              let dot = weekDots.first(where: { $0.dayIndex == day }), dot.isJumpable else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            selectedDayIndex = day
            carouselState = nil
        }
    }


    // MARK: Hero — ring + rating word + the hour carousel

    private var heroCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 4) {
                ScoreRingView(score: selectedDay?.score,
                              tint: Theme.ratingTint(selectedDay?.rating),
                              style: .hero)
                Text(selectedDay?.ratingDisplay ?? "No Window")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ratingTint(selectedDay?.rating))
                    .fixedSize()
            }
            .frame(width: 64)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("detail.score")
            .accessibilityLabel(scoreAccessibilityLabel)

            carouselBlock
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
        let verdict = selectedDay?.ratingDisplay ?? "No Window"
        guard let score = selectedDay?.score else { return "\(verdict), no score" }
        return "\(verdict), score \(score) out of 100"
    }

    /// `−` · pill row · `+` on one line, the return-to-range control centred
    /// under it. The return slot keeps its height while hidden so the row
    /// never jumps when it appears.
    private var carouselBlock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                stepButton(systemName: "minus",
                           enabled: carousel?.canStepBack ?? false,
                           identifier: "detail.stepBack") { move(by: -1) }
                pillTrack
                stepButton(systemName: "plus",
                           enabled: carousel?.canStepForward ?? false,
                           identifier: "detail.stepForward") { move(by: 1) }
            }
            ZStack {
                if carousel?.canReturnToRange == true {
                    returnButton
                        .transition(.opacity)
                }
            }
            .frame(height: Self.rowHeight)
        }
        .frame(maxWidth: .infinity)
    }

    /// 20×20 r5 pill, 10pt glyph; the LAYOUT stays 20pt while the ±12pt
    /// padding pair grows the hit area to the HIG 44pt (the beta pill's
    /// pattern).
    private func stepButton(systemName: String,
                            enabled: Bool,
                            identifier: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accentInteractive)
                .frame(width: 20, height: 20)
                .background(Theme.timelineTrack, in: RoundedRectangle(cornerRadius: 5))
                .opacity(enabled ? 1 : 0.35)
                .padding(12)
                .contentShape(Rectangle())
                .padding(-12)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(systemName == "minus" ? "Earlier hours" : "Later hours")
    }

    /// Icon-only, 40×26 capsule; a ±9pt padding pair makes the 44pt target.
    private var returnButton: some View {
        Button(action: returnToRange) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentInteractive)
                .frame(width: 40, height: Self.rowHeight)
                .background(Theme.accentInteractive.opacity(0.12), in: Capsule())
                .padding(9)
                .contentShape(Rectangle())
                .padding(-9)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.returnToRange")
        .accessibilityLabel("Return to your range")
    }

    /// Every walkable hour of the shown day is a slot; `visibleSlots` of them
    /// show, equal widths with 3pt gaps filling the track. The whole row
    /// slides (offset by `firstVisible`) and is clipped to the track. A
    /// horizontal drag steps the span one hour per pill pitch, finger-left =
    /// later hours. Tapping a pill does nothing.
    @ViewBuilder
    private var pillTrack: some View {
        if let carousel, let authored {
            let slots = CGFloat(carousel.visibleSlots)
            let pillWidth = max((trackWidth - (slots - 1) * Self.pillGap) / slots, 1)
            let pitch = pillWidth + Self.pillGap
            // The track's size is the clear base (full width × 26); the pill
            // row rides in an overlay so its overflow never feeds back into
            // the measured width.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
                .overlay(alignment: .leading) {
                    HStack(spacing: Self.pillGap) {
                        ForEach(Array(carousel.walkable), id: \.self) { index in
                            pill(at: index,
                                 authored: authored,
                                 chosen: carousel.span.contains(index))
                                .frame(width: pillWidth, height: Self.rowHeight)
                        }
                    }
                    .fixedSize()
                    .offset(x: -CGFloat(carousel.firstVisible - carousel.walkable.lowerBound) * pitch)
                }
                .clipped()
                .contentShape(Rectangle())
                // Simultaneous so a vertical scroll starting on the row still
                // scrolls the page; the span steps as the drag crosses each
                // pill pitch, and any steps a fast flick skipped land on end.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            dragStep(to: value.translation, pitch: pitch)
                        }
                        .onEnded { value in
                            dragStep(to: value.translation, pitch: pitch)
                            dragSteps = 0
                        }
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trackWidth = $0 }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("detail.hourStrip")
                .accessibilityLabel(spanAccessibilityLabel(carousel))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: move(by: 1)
                    case .decrement: move(by: -1)
                    @unknown default: break
                    }
                }
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
        }
    }

    /// "Hours 6am to 10am" — the span's first hour to its exclusive end, the
    /// way the Range itself is phrased.
    private func spanAccessibilityLabel(_ carousel: HourCarousel) -> String {
        guard let deriver else { return "Hours" }
        return "Hours \(deriver.hourLabel(at: carousel.span.lowerBound)) to \(deriver.hourLabel(at: carousel.span.upperBound))"
    }

    /// The old pill look: r6, tier colour, white 11pt numeral (Semibold when
    /// chosen). Chosen hours 100%, the rest 35%. A PASSED hour is grey but
    /// readable — its fill drops to 15% and its numeral turns secondary; the
    /// 35% dim then applies to its fill only, so the numeral stays legible.
    private func pill(at index: Int, authored: AuthoredActivity, chosen: Bool) -> some View {
        let tier = viewModel.forecast.flatMap { forecast -> HourTier? in
            guard forecast.hours.indices.contains(index) else { return nil }
            return HourQuality.tier(for: forecast.hours[index], thresholds: authored.thresholds)
        }
        let fill = tier.map(Theme.tierColor) ?? Theme.timelineTrack
        let passed = deriver?.hasPassed(index, now: now()) ?? false
        let dim: Double = chosen ? 1 : 0.35
        return RoundedRectangle(cornerRadius: 6)
            .fill(fill.opacity(passed ? 0.15 * dim : 1))
            .overlay(
                Text(RangeStripAxis.numeral(viewModel.localHour(at: index) ?? 0))
                    .font(.system(size: 11, weight: chosen ? .semibold : .medium))
                    .foregroundStyle(passed ? Theme.secondaryText : Color.white)
            )
            .opacity(passed ? 1 : dim)
    }

    private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    private func move(by delta: Int) {
        guard var next = carousel else { return }
        next.step(by: delta)
        withAnimation(animation) { carouselState = next }
    }

    /// Finger-left = later hours. Horizontal-dominant drags only, so a
    /// vertical page scroll never slides the span.
    private func dragStep(to translation: CGSize, pitch: CGFloat) {
        guard abs(translation.width) > abs(translation.height), pitch > 0 else { return }
        let target = Int((-translation.width / pitch).rounded(.towardZero))
        let delta = target - dragSteps
        guard delta != 0 else { return }
        dragSteps = target
        move(by: delta)
    }

    private func returnToRange() {
        guard var next = carousel else { return }
        next.returnToRange()
        withAnimation(animation) { carouselState = next }
    }

    // MARK: The metric cards — two per row, the chosen hours' average

    /// ONE card per display metric, in the Activity's own order. The frames
    /// drew a three-metric Activity and never ruled on more — and every
    /// thresholded metric needs a surface somewhere (the v2 card dropped the
    /// chips), so a fourth metric gets a fourth card rather than vanishing.
    private var metricGrid: some View {
        let metrics = current.displayMetrics
        let inRange = carousel?.overlapsRange ?? false
        let hour = displayedHour
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 13),
                                   GridItem(.flexible(), spacing: 13)],
                         spacing: 12) {
            ForEach(metrics, id: \.self) { metric in
                MetricCardView(metric: metric,
                               hour: hour,
                               threshold: authored?.thresholds[metric],
                               verdict: verdict(for: metric, hour: hour, inRange: inRange),
                               catalog: catalog,
                               windUnit: windUnit)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    /// A span entirely outside the Range is not judged, so the value renders
    /// uncoloured; overlapping it, the averaged reading is coloured.
    private func verdict(for metric: String, hour: HourlyWeather?, inRange: Bool) -> HourTier? {
        guard inRange, let hour else { return nil }
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
