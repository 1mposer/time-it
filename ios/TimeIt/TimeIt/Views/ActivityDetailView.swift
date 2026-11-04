import SwiftUI

/// Activity Detail v3 (Figma `456:358` / `464:2348`, owner-approved
/// 2026-09-30; day-jump `508:417`, owner-approved 2026-10-02; hero carousel —
/// depth & polish pass build 8, owner rulings 2026-10-31 / 2026-11-01 /
/// 2026-11-03 / 2026-11-04). Opens on TODAY. Top to bottom: the week-dot row
/// (the day-jump control — ring on the selected day), the hero (the 64pt
/// day-score ring + rating word, and beside it the hour row: `−` · a
/// natively scrolling strip of tier-coloured hour pills · `+`, with one line
/// under it naming the hours the cards show), square metric cards two per
/// row AVERAGING the chosen hours, then the Edit range / Edit metrics list.
///
/// The row always shows the FULL Range: hours of it before the forecast
/// start are drawn grey with no data. No Calculate button: the cards
/// recompute live as the row settles, the Range's home slots keep a faint
/// ghost outline while the span drifts, and the line's return button (or a
/// tap on the ring) springs the row home.
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
    /// The pill row's scroll position — the leading visible slot's id. The
    /// ONE piece of carousel state: the span derives from it
    /// (`HourCarousel.span(forScrollAnchor:)`). nil = the opening state.
    @State private var scrolledSlot: Int?
    /// The measured width of the pill viewport between `−` and `+`.
    @State private var trackWidth: CGFloat = 0
    /// Bumped when the ring springs the row home — the impact haptic.
    @State private var homeTick = 0
    /// Bumped when the span moves to a new hour by − / + or the user's own
    /// scroll — the selection haptic. Returning home and day jumps don't.
    @State private var selectionTick = 0
    /// The slot a programmatic scroll (− / +, home, re-seed) is heading for:
    /// its arrival in `scrolledSlot` is not a user scroll, so no tick.
    @State private var programmaticSlot: Int?
    /// The open edit door: which Activity and which wizard tab it lands on.
    @State private var editing: EditRequest?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Layout = Theme.Detail

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

    /// The shown day's FULL Range as global positions — hours before the
    /// forecast start are negative and carry no data (owner ruling
    /// 2026-11-04: the row always shows the whole authored Range).
    private var rangeHours: Range<Int>? {
        authored.flatMap { viewModel.rangeSlotPositions(for: $0, dayIndex: selectedDayIndex) }
    }

    /// Every hour the carousel may show on the shown day.
    private var walkable: Range<Int>? {
        authored.flatMap { viewModel.walkableHourRange(for: $0, dayIndex: selectedDayIndex) }
    }

    /// The carousel as it opens for the shown day and row width (span on the
    /// Range); nil until a forecast exists. A change re-seeds the row.
    private var openingCarousel: HourCarousel? {
        guard let walkable, !walkable.isEmpty else { return nil }
        let slots = HourCarousel.visibleSlotCount(rangeLength: rangeHours?.count ?? 1,
                                                  availableWidth: Double(trackWidth),
                                                  gap: Double(Layout.pillGap))
        return HourCarousel(walkable: walkable, rangeHours: rangeHours, visibleSlots: slots)
    }

    /// The live carousel: the opening one settled on the row's scroll
    /// position.
    private var carousel: HourCarousel? {
        guard var carousel = openingCarousel else { return nil }
        if let scrolledSlot { carousel.settle(onScrollAnchor: scrolledSlot) }
        return carousel
    }

    /// The chosen span's slots — the metric cards and the line read them.
    private var displayedSlots: [HourSlot] {
        carousel.map { viewModel.slots(in: $0.span) } ?? []
    }

    /// The chosen hours folded into one reading (`HourAggregate`) — only the
    /// slots with data count; an all-gone span is nil, so the cards show "—".
    private var displayedHour: HourlyWeather? {
        HourAggregate.aggregate(slots: displayedSlots, hours: viewModel.forecast?.hours ?? [])
    }

    /// The line under the row: "Your range …" on the Range, "Showing …" plus
    /// the return button away from it. Derived from the same `carousel` as
    /// the cards, so both change on the same settle. Nil without a Range.
    private var rangeLine: RangeLine? {
        guard let carousel, carousel.rangeHours != nil,
              let window = authored?.window, let deriver else { return nil }
        return RangeLine(window: window,
                         isAtRange: carousel.isAtRange,
                         spanStartHour: deriver.localHour(at: carousel.span.lowerBound),
                         spanEndHour: deriver.localHour(at: carousel.span.upperBound))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.dotsToHero) {
                if !weekDots.isEmpty {
                    WeekDotsView(dots: weekDots,
                                 ringedDayIndex: selectedDayIndex,
                                 onTap: jump(to:),
                                 identifierPrefix: "detail.weekDot")
                }
                VStack(alignment: .leading, spacing: Layout.sectionGap) {
                    heroCard
                    metricGrid
                    editCard
                }
            }
            .padding(.horizontal, Layout.sideMargin)
            .padding(.top, Layout.topPadding)
            .padding(.bottom, Layout.sideMargin)
        }
        .background(Theme.appBackground)
        // Re-base guard: a refetch across a day rollover shifts what each
        // dayIndex / hours[] index means, so a stale selection would point at
        // a shifted or absent day — reset to today, carousel back on the Range.
        .onChange(of: viewModel.forecast?.forecastStart) { _, _ in
            selectedDayIndex = 0
            seed(openingCarousel?.scrollAnchor)
        }
        // A new day or row width re-opens the row on that day's Range.
        .onChange(of: openingCarousel) { _, opening in
            seed(opening?.scrollAnchor)
        }
        // A user scroll that lands the span on a new hour ticks; a
        // programmatic scroll's arrival does not.
        .onChange(of: scrolledSlot) { old, new in
            if let target = programmaticSlot, new == target {
                programmaticSlot = nil
                return
            }
            guard let opening = openingCarousel, let old, let new,
                  opening.span(forScrollAnchor: old) != opening.span(forScrollAnchor: new) else { return }
            selectionTick += 1
        }
        .sensoryFeedback(.selection, trigger: selectionTick)
        .sensoryFeedback(.impact(weight: .light), trigger: homeTick)
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
    /// re-read for it, and the carousel re-opens on its Range (the
    /// `openingCarousel` change re-seeds the row).
    /// A day absent from `days[]` or with no data is not a target, and
    /// tapping the already-ringed dot is a no-op (it must not reset the
    /// carousel).
    private func jump(to day: Int) {
        guard day != selectedDayIndex,
              let dot = weekDots.first(where: { $0.dayIndex == day }), dot.isJumpable else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            selectedDayIndex = day
        }
    }

    // MARK: Hero — ring + rating word, the hour row beside it

    /// Owner ruling 2026-11-04: ring 64 inset 16 from the top and left, the
    /// word 12 under it, 16 to the bottom. The row column runs from the
    /// ring's right edge + 16 to the right inset: the pill row, and 8 under
    /// it the line. Alone, the row sits on the ring's centre line; with the
    /// line, the row + line block centres on the ring column. The hero is
    /// the taller column plus the insets (`Theme.Detail.heroHeight`).
    private var heroCard: some View {
        let line = rangeLine
        let hasLine = line != nil
        return HStack(alignment: .top, spacing: Layout.ringToRow) {
            ringButton
            VStack(alignment: .leading, spacing: Layout.rowToLine) {
                carouselRow
                    .frame(height: Layout.pillHeight)
                if let line {
                    rangeLineView(line)
                        .frame(height: Layout.lineHeight)
                }
            }
            .padding(.top, Layout.rowColumnTop(hasLine: hasLine))
        }
        .frame(height: Layout.heroHeight(hasLine: hasLine) - Layout.heroInset - Layout.heroBottom,
               alignment: .top)
        .padding(EdgeInsets(top: Layout.heroInset, leading: Layout.heroInset,
                            bottom: Layout.heroBottom, trailing: Layout.heroInset))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .cardFloat()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var canReturn: Bool { carousel?.canReturnToRange ?? false }

    /// The ring belongs to the Range: tapping it springs the row home — the
    /// second way home beside the line's return button (owner ruling
    /// 2026-11-04 moved `detail.returnToRange` to that button). Press
    /// feedback lands on touch-down; the button is inert on the Range. The
    /// day score (`detail.score`) is an overlay element of its own.
    private var ringButton: some View {
        VStack(spacing: Layout.ringToWord) {
            Button(action: returnToRange) {
                ScoreRingView(score: selectedDay?.score,
                              tint: Theme.ratingTint(selectedDay?.rating),
                              style: .hero)
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .disabled(!canReturn)
            .accessibilityHidden(true)
            Text(selectedDay?.ratingDisplay ?? "No Window")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ratingTint(selectedDay?.rating))
                .fixedSize()
                .frame(height: Layout.wordHeight)
        }
        .frame(width: Layout.ringDiameter, height: Layout.ringColumnHeight, alignment: .top)
        .overlay {
            Color.clear
                .accessibilityElement()
                .accessibilityIdentifier("detail.score")
                .accessibilityLabel(scoreAccessibilityLabel)
                .allowsHitTesting(false)
        }
    }

    /// "Your range 6 – 10am" / "Showing 7 – 11am" + return — 13pt secondary
    /// text; the swap rolls (`numericText`), the return button fades in at
    /// the line's end.
    private func rangeLineView(_ line: RangeLine) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(line.text)
                .font(.system(size: Layout.lineFont))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .accessibilityIdentifier("detail.rangeLine")
            if line.showsReturn {
                returnButton
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : Theme.Motion.value, value: line)
    }

    /// The line's return button: a 12pt Semibold `arrow.uturn.backward` in a
    /// 24×24 capsule hit shape, padded to the HIG 44pt target. Springs the
    /// row home exactly like the ring tap.
    private var returnButton: some View {
        Button(action: returnToRange) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentInteractive)
                .frame(width: Layout.returnPiece, height: Layout.returnPiece)
                .contentShape(Capsule())
                .padding(Layout.hitPad)
                .contentShape(Rectangle())
                .padding(-Layout.hitPad)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("detail.returnToRange")
        .accessibilityLabel("Return to your range")
    }

    private var scoreAccessibilityLabel: String {
        let verdict = selectedDay?.ratingDisplay ?? "No Window"
        guard let score = selectedDay?.score else { return "\(verdict), no score" }
        return "\(verdict), score \(score) out of 100"
    }

    /// `−` · pill viewport · `+` filling the column, 4pt apart. Under
    /// iOS 26 the two pieces are Liquid Glass in one container.
    private var carouselRow: some View {
        GlassGroup(spacing: Layout.stepToViewport) {
            HStack(spacing: Layout.stepToViewport) {
                stepButton(systemName: "minus",
                           enabled: carousel?.canStepBack ?? false,
                           identifier: "detail.stepBack") { move(by: -1) }
                pillViewport
                stepButton(systemName: "plus",
                           enabled: carousel?.canStepForward ?? false,
                           identifier: "detail.stepForward") { move(by: 1) }
            }
        }
    }

    /// A 24×24 r6 piece (a pill's size), 10pt glyph; the layout stays 24pt
    /// while a ±10pt padding pair grows the hit area to the HIG 44pt.
    private func stepButton(systemName: String,
                            enabled: Bool,
                            identifier: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accentInteractive)
                .opacity(enabled ? 1 : 0.35)
                .frame(width: Layout.stepPiece, height: Layout.stepPiece)
                .stepPieceSurface(enabled: enabled)
                .padding(Layout.hitPad)
                .contentShape(Rectangle())
                .padding(-Layout.hitPad)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(systemName == "minus" ? "Earlier hours" : "Later hours")
    }

    /// The pill viewport: a native horizontal scroll of every walkable hour
    /// (plus blank pads at the walk ends), snapping by pill pitch, so a drag
    /// gets UIKit's tracking, deceleration and rubber band. The span is the
    /// run of pills under the fixed highlight window; it derives from the
    /// scroll position. Tapping a pill does nothing.
    @ViewBuilder
    private var pillViewport: some View {
        // The clear base sizes the viewport (full width × 24); the scroll row
        // rides in an overlay so it never feeds back into the measurement.
        let base = Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Layout.pillHeight)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trackWidth = $0 }
        if let carousel, let authored, trackWidth > 0 {
            let pillWidth = CGFloat(HourCarousel.pillWidth(slots: carousel.visibleSlots,
                                                           availableWidth: Double(trackWidth),
                                                           gap: Double(Layout.pillGap)))
            let compact = Double(pillWidth) < HourCarousel.compactPillWidth
            base
                .overlay(alignment: .leading) {
                    ScrollView(.horizontal) {
                        HStack(spacing: Layout.pillGap) {
                            ForEach(Array(carousel.slotIDs), id: \.self) { id in
                                slot(id, carousel: carousel, authored: authored, compact: compact)
                                    .frame(width: pillWidth, height: Layout.pillHeight)
                                    .id(id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .frame(width: trackWidth, height: Layout.pillHeight)
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $scrolledSlot, anchor: .leading)
                    .onAppear {
                        if scrolledSlot == nil { seed(carousel.scrollAnchor) }
                    }
                }
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
                .accessibilityActions {
                    if carousel.canReturnToRange {
                        Button("Return to your range", action: returnToRange)
                    }
                }
        } else {
            base
        }
    }

    /// "Hours 6am to 10am" — the span's first hour to its exclusive end, the
    /// way the Range itself is phrased.
    private func spanAccessibilityLabel(_ carousel: HourCarousel) -> String {
        guard let deriver else { return "Hours" }
        return "Hours \(deriver.hourLabel(at: carousel.span.lowerBound)) to \(deriver.hourLabel(at: carousel.span.upperBound))"
    }

    /// One slot: a blank pad outside the walk, else an hour pill. Pills off
    /// the viewport's edges fade and shrink slightly as they scroll out, so
    /// the row reads as a continuous strip.
    @ViewBuilder
    private func slot(_ id: Int, carousel: HourCarousel, authored: AuthoredActivity, compact: Bool) -> some View {
        if carousel.walkable.contains(id) {
            pill(at: id,
                 authored: authored,
                 compact: compact,
                 chosen: carousel.span.contains(id),
                 home: !carousel.isAtRange && (carousel.rangeHours?.contains(id) ?? false))
                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                    let edge = reduceMotion ? 0 : min(abs(phase.value), 1)
                    return content
                        .opacity(1 - 0.5 * edge)
                        .scaleEffect(1 - 0.12 * edge)
                }
        } else {
            Color.clear
        }
    }

    /// The round-2 pill: r6, tier colour, white 11pt numeral (Semibold when
    /// chosen; 9pt Semibold on a pill narrower than 22pt — a long Range).
    /// Chosen hours 100%, the rest 35%. A PASSED hour — or one with no data,
    /// like a gone hour before the forecast start (owner ruling 2026-11-04) —
    /// is the grey track with a secondary numeral and no tier colour; off the
    /// span its track fill dims to 50% (35% of the track would vanish on
    /// white) and the numeral stays legible.
    /// A Range ("home") hour keeps a 1pt ghost outline inside its rect while
    /// the span is away.
    private func pill(at index: Int, authored: AuthoredActivity, compact: Bool, chosen: Bool, home: Bool) -> some View {
        let hasPassed = deriver?.hasPassed(index, now: now()) ?? false
        let tier = viewModel.forecast.flatMap { forecast -> HourTier? in
            guard !hasPassed, forecast.hours.indices.contains(index) else { return nil }
            return HourQuality.tier(for: forecast.hours[index], thresholds: authored.thresholds)
        }
        // No tier = passed or no data: drawn grey either way.
        let passed = tier == nil
        let fill = tier.map(Theme.tierColor) ?? Theme.timelineTrack
        let dim: Double = chosen ? 1 : 0.35
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sm)
        return shape
            .fill(fill.opacity(passed ? (chosen ? 1 : 0.5) : 1))
            .overlay(
                Text(RangeStripAxis.numeral(viewModel.localHour(at: index) ?? 0))
                    .font(compact ? .system(size: 9, weight: .semibold)
                                  : .system(size: 11, weight: chosen ? .semibold : .medium))
                    .foregroundStyle(passed ? Theme.secondaryText : Color.white)
            )
            .opacity(passed ? 1 : dim)
            .overlay(
                shape
                    .strokeBorder(Theme.homeOutline, lineWidth: Theme.homeOutlineWidth)
                    .opacity(home ? 1 : 0)
            )
            .animation(reduceMotion ? nil : Theme.Motion.value, value: chosen)
            .animation(reduceMotion ? nil : Theme.Motion.value, value: home)
    }

    /// − / + slide the row one pill; the span follows the scroll position.
    private func move(by delta: Int) {
        guard let start = carousel else { return }
        var next = start
        next.step(by: delta)
        guard next.span != start.span else { return }
        selectionTick += 1
        scroll(to: next.scrollAnchor, animation: Theme.Motion.step)
    }

    /// Scrolls the row to `slot`, marking it programmatic.
    private func scroll(to slot: Int, animation: Animation?) {
        guard slot != scrolledSlot else { return }
        programmaticSlot = slot
        withAnimation(reduceMotion ? nil : animation) {
            scrolledSlot = slot
        }
    }

    /// Puts the row on `slot` with no animation and no haptic — the opening
    /// position for a day, a width, or a re-based forecast.
    private func seed(_ slot: Int?) {
        guard let slot else { scrolledSlot = nil; return }
        scroll(to: slot, animation: nil)
    }

    /// The ring's action: spring the row back onto the Range.
    private func returnToRange() {
        guard var next = carousel, next.canReturnToRange else { return }
        next.returnToRange()
        homeTick += 1
        scroll(to: next.scrollAnchor, animation: Theme.Motion.home)
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
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: Layout.gridColumnGap),
                                   GridItem(.flexible(), spacing: Layout.gridColumnGap)],
                         spacing: Layout.gridRowGap) {
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
                .padding(.leading, Layout.sideMargin)
            editRow("Edit metrics", identifier: "detail.editMetrics") {
                if let authored { editing = EditRequest(activity: authored, step: .metrics) }
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .cardFloat()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
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
            .padding(.horizontal, Layout.sideMargin)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: Liquid Glass (experimental, iOS 26+)

/// Groups the hero row's glass pieces so they blend as one material under
/// iOS 26; a plain pass-through below it.
private struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

private extension View {
    /// The − / + piece's surface: interactive Liquid Glass on iOS 26, the
    /// flat recess-track fill below it.
    @ViewBuilder
    func stepPieceSurface(enabled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sm)
        if #available(iOS 26, *) {
            self.glassEffect(enabled ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(Theme.timelineTrack, in: shape)
        }
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

/// HIG check: the hero and cards at the accessibility XL text size.
#Preview("Cycling (Accessibility XL)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[0],
                           viewModel: viewModel)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
    .task { await viewModel.loadForecast() }
}
#endif
