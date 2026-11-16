import SwiftUI

/// Activity Detail — lane RETHINK (Figma Mess around "Final - Opus v2",
/// owner-approved 2026-11-16; detail v3 lineage `456:358`). Top to bottom:
/// the week-dot row (the day-jump control), on the tomorrow detail after
/// today's hours passed the "Today's hours are over" row, the HERO with its
/// Report / Explore switch, the metric cards averaging the shown hours, the
/// Coming days list (tomorrow detail only), then the Range / Metrics edit
/// circles and Delete.
///
/// Report (default, remembered per Activity): the day-score ring + caption
/// ("Average", "Tomorrow" on the passed-day tomorrow), the verdict line
/// "7 – 10am · Perfect", the Range strip with its integers and "Your hours
/// 6 – 10am". Explore: the ring, `−` hour pills `+` (the carousel — the
/// Best hours window marked by a green bar under its pills), then the rows
/// Your hours (range · Average N) / Best hours (window · verdict) / Looking
/// at (span · Average N, only off the Range, highlighted) and a full-width
/// "Back to 6 – 10am" pill. The looked-at span's score is the SERVER's
/// (`DashboardViewModel.scoreSpan`, fetched as the row settles — no client
/// formula); it is keyed on exactly what it scored and cleared the moment
/// the span, the day or the forecast changes, so a stale reply never lands.
/// The ring shows the looked-at span's score while there is one, else the
/// day's — always tinted by its score band (owner ruling 02 a).
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
    /// Pops the detail once its Activity is deleted (here or from the
    /// editor) — the dashboard owns the navigation path (an `@Environment(\.dismiss)` read
    /// here kept the pushed detail re-rendering and starved XCUI).
    var onActivityDeleted: () -> Void = {}

    /// The day the detail shows — opens on the day it was opened for (today
    /// from a card tap, the tapped day from a card's week dot — note 16);
    /// the week-dot row jumps it (spec 05 day-jump, frame `508:417`).
    @State private var selectedDayIndex: Int

    init(activity: ActivityRating,
         viewModel: DashboardViewModel,
         catalog: MetricCatalogProviding = StaticMetricCatalog(),
         windUnit: WindSpeedUnit = .kmh,
         now: @escaping () -> Date = Date.init,
         initialDayIndex: Int = 0,
         onActivityDeleted: @escaping () -> Void = {}) {
        self.activity = activity
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.catalog = catalog
        self.windUnit = windUnit
        self.now = now
        self.onActivityDeleted = onActivityDeleted
        _selectedDayIndex = State(initialValue: initialDayIndex)
        _heroMode = State(initialValue: viewModel.preferences.heroMode(for: activity.activityId))
    }
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
    /// Single-use, so an interrupted scroll can never leave it stale.
    @State private var scrollMarker = ProgrammaticScrollMarker()
    /// The open edit door: which Activity and which wizard tab it lands on.
    @State private var editing: EditRequest?
    /// The server's score for a span, keyed on exactly what it scored — the
    /// ring reads it only while that key is the one on screen.
    @State private var scoredSpan: ScoredSpan?
    /// The edit circles' own lift ticks (one each, so only the tapped circle
    /// lifts) and their shared impact haptic.
    @State private var rangeLiftTick = 0
    @State private var metricsLiftTick = 0
    @State private var editTick = 0
    /// Report / Explore — remembered per Activity (PreferencesStore).
    @State private var heroMode: HeroMode
    /// The looked-at span's server score in flight.
    @State private var scoringTask: Task<Void, Never>?
    /// The hours-over row has been tapped away (it then stays away for the
    /// rest of the local day — PassedDayStore).
    @State private var hoursOverGone = false
    /// The detail's Delete is awaiting its confirmation.
    @State private var confirmingDelete = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Accessibility sizes stack the hero and single-column the grid.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private typealias Layout = Theme.Detail
    private typealias Hero = RethinkLayout.Hero

    /// Accessibility sizes put the hero's text column under the ring.
    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    private struct EditRequest: Identifiable {
        let activity: AuthoredActivity
        let step: EditorStep
        var id: String { activity.id }
    }

    /// What a span score belongs to: the span, the day, the forecast and
    /// the authored Activity as sent — a thresholds-only edit refetches the
    /// same forecast, so without `input` the old score would survive it.
    private struct SpanKey: Equatable {
        let span: Range<Int>
        let dayIndex: Int
        let forecastStart: String
        let input: ActivityInput
    }

    private struct ScoredSpan: Equatable {
        let key: SpanKey
        let result: SpanScore
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

    /// What the cards read: the shown hours folded into one reading (`HourAggregate`) — only the slots with data
    /// count; an all-gone span is nil, so the cards show "—".
    private var displayedHour: HourlyWeather? {
        HourChips.reading(slots: displayedSlots, hours: viewModel.forecast?.hours ?? [],
                          selected: nil)
    }

    // MARK: Span scoring state (owner rulings 2026-11-04)

    /// The span on screen as a span-score key; nil without a carousel.
    private var spanKey: SpanKey? {
        guard let carousel, let authored, let start = viewModel.forecast?.forecastStart else { return nil }
        return SpanKey(span: carousel.span, dayIndex: selectedDayIndex, forecastStart: start,
                       input: authored.activityInput)
    }

    /// The span score the ring shows — only the CURRENT span's.
    private var shownSpanScore: SpanScore? {
        guard let scoredSpan, scoredSpan.key == spanKey else { return nil }
        return scoredSpan.result
    }

    // MARK: Passed day (lane RETHINK, owner ruling 05 a)

    /// Today's hours are over for this Activity.
    private var hasPassedToday: Bool { viewModel.hasPassedToday(activityId: activity.activityId) }

    /// The passed-day tomorrow: the detail it opens on.
    private var isPassedTomorrow: Bool { hasPassedToday && selectedDayIndex == 1 }

    /// The hours-over row: on the passed-day tomorrow, until tapped away.
    private var showsHoursOver: Bool {
        isPassedTomorrow && !hoursOverGone
            && !viewModel.passedDayEntry(activityId: activity.activityId).rowDismissed
    }

    private var ringCaption: String { isPassedTomorrow ? "Tomorrow" : "Average" }

    /// The authored Range as "6 – 10am".
    private var rangeLabel: String? { authored?.window.map(RangeText.chipLabel) }

    // MARK: Explore state

    /// The looked-at span as "7 – 11am"; nil on the Range.
    private var lookedAtLabel: String? {
        guard heroMode == .explore, let carousel, !carousel.isAtRange, let deriver,
              let window = SpanScoring.window(for: carousel.span, deriver: deriver) else { return nil }
        return RangeText.chipLabel(window)
    }

    /// The ring's score: the looked-at span's (Explore, off the Range, once
    /// the server answers), else the shown day's.
    private var ringScore: Int? {
        if lookedAtLabel != nil, let shown = shownSpanScore { return shown.score }
        return selectedDay?.score
    }

    private var verdictLine: VerdictLine { VerdictLine(day: selectedDay, deriver: deriver) }

    private var exploreRows: [ExploreRows.Row] {
        ExploreRows.rows(range: rangeLabel ?? "\u{2014}",
                         dayScore: selectedDay?.score,
                         best: verdictLine,
                         lookingAt: lookedAtLabel.map { .init(span: $0, score: shownSpanScore?.score) })
    }

    /// Cross-fades under Reduce Motion.
    private var fade: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RethinkLayout.gap) {
                if !weekDots.isEmpty {
                    WeekDotsView(dots: weekDots,
                                 ringedDayIndex: selectedDayIndex,
                                 dimmedDayIndex: hasPassedToday ? 0 : nil,
                                 onTap: jump(to:),
                                 identifierPrefix: "detail.weekDot")
                }
                if showsHoursOver {
                    HoursOverRow(morning: viewModel.passedDayEntry(activityId: activity.activityId).morning) {
                        withAnimation(HoursOverRow.removalAnimation(reduceMotion: reduceMotion)) {
                            hoursOverGone = true
                        }
                        viewModel.dismissHoursOverRow(activityId: activity.activityId)
                    }
                    .transition(HoursOverRow.removal(reduceMotion: reduceMotion))
                }
                // A minute tick scoped to the hero (build-8 deferral 5):
                // passed pills grey on the minute. Nothing faster — a
                // constantly re-rendering pushed detail starves XCUI.
                TimelineView(.everyMinute) { _ in
                    heroCard
                }
                metricGrid
                if isPassedTomorrow, let deriver {
                    let rows = ComingDays.rows(for: current, after: selectedDayIndex, deriver: deriver)
                    if !rows.isEmpty { ComingDaysCard(rows: rows) }
                }
                editCircles
                    .padding(.top, RethinkLayout.Grid.x2)
                deleteButton
            }
            .padding(.horizontal, RethinkLayout.margin)
            .padding(.top, Layout.topPadding)
            .padding(.bottom, RethinkLayout.margin)
        }
        .background(Theme.appBackground)
        // Re-base guard: a refetch across a day rollover shifts what each
        // dayIndex / hours[] index means — back to the OPENING day (tomorrow
        // once today's hours are over), carousel back on the Range.
        .onChange(of: viewModel.forecast?.forecastStart) { _, _ in
            selectedDayIndex = viewModel.shownCardDay(forActivityId: activity.activityId).dayIndex
            seed(openingCarousel?.scrollAnchor)
        }
        // A new day or row width re-opens the row on that day's Range.
        .onChange(of: openingCarousel) { _, opening in
            seed(opening?.scrollAnchor)
        }
        // A user scroll that lands the span on a new hour ticks; a
        // programmatic scroll's arrival does not.
        .onChange(of: scrolledSlot) { old, new in
            if scrollMarker.consume(new) { return }
            guard let opening = openingCarousel, let old, let new,
                  opening.span(forScrollAnchor: old) != opening.span(forScrollAnchor: new) else { return }
            selectionTick += 1
        }
        // The clearing rule: a new span, a day jump or a refetch drops the
        // span score; a settled span off the Range asks the server again.
        .onChange(of: spanKey) { _, _ in
            clearSpanScore()
            scheduleSpanScore()
        }
        .onChange(of: heroMode) { _, mode in
            viewModel.preferences.setHeroMode(mode, for: activity.activityId)
            // Report always describes the Range: the row springs home.
            if mode == .report { returnToRange() } else { scheduleSpanScore() }
        }
        .sensoryFeedback(.selection, trigger: selectionTick)
        .sensoryFeedback(.impact(weight: .light), trigger: homeTick)
        .sensoryFeedback(.impact(weight: .light), trigger: editTick)
        .navigationTitle(current.label)
        .navigationBarTitleDisplayMode(.inline)
        // The circles are the detail's edit doors; the editor keeps its
        // Delete too. A Activity deleted there pops the detail as the sheet
        // closes: `authored` reads the store, so it is nil the moment the
        // delete lands (no refetch wait).
        .sheet(item: $editing, onDismiss: {
            if authored == nil { onActivityDeleted() }
        }) { request in
            NavigationStack {
                ActivityEditorView(existing: request.activity,
                                   isNew: false,
                                   initialStep: request.step,
                                   windUnit: windUnit,
                                   onSave: { viewModel.store.update($0) },
                                   onDelete: { viewModel.store.delete(id: request.activity.id) },
                                   reviewPreview: { await viewModel.reviewPreview(for: $0) },
                                   rangeHasPassedToday: { viewModel.rangeHasPassedToday($0) })
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
              let dot = weekDots.first(where: { $0.dayIndex == day }),
              dot.isJumpable || (day == 0 && hasPassedToday) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            selectedDayIndex = day
        }
    }

    // MARK: Hero — Report / Explore (Figma v2 frames 2, 4, 6)

    /// Ring column | text column, 16 inset, r24 superellipse. At
    /// accessibility sizes the text column drops under the ring.
    private var heroCard: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Hero.columnGap))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Hero.columnGap))
        return VStack(alignment: .leading, spacing: Hero.headerToRows) {
            layout {
                ringColumn
                VStack(alignment: .leading, spacing: 0) {
                    switch heroMode {
                    case .report: reportColumn
                    case .explore: exploreColumn
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if heroMode == .explore {
                exploreRowsView
                if lookedAtLabel != nil, let rangeLabel {
                    backPill(rangeLabel)
                        .padding(.top, Hero.rowsToBack - Hero.headerToRows + RethinkLayout.Grid.x2)
                        .transition(.opacity)
                }
            }
        }
        .animation(fade, value: heroMode)
        .animation(fade, value: lookedAtLabel)
        .padding(RethinkLayout.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.detailContainer)
        .clipShape(RethinkLayout.shape())
        .cardLift(cornerRadius: RethinkLayout.outerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.hero")
    }

    /// The 64pt ring + its caption. Tapping the ring springs the row home
    /// (Explore, off the Range); the spoken summary is its own element.
    private var ringColumn: some View {
        VStack(spacing: Hero.ringToCaption) {
            Button(action: returnToRange) {
                ScoreRingView(score: ringScore, tint: Theme.scoreBandTint(ringScore), style: .hero)
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .disabled(!(carousel?.canReturnToRange ?? false))
            .accessibilityHidden(true)
            Text(ringCaption)
                .scaledFont(size: Hero.captionFont, weight: .semibold, maxSize: 17)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .frame(minWidth: Hero.ringDiameter)
        .overlay {
            Color.clear
                .accessibilityElement()
                .accessibilityIdentifier("detail.score")
                .accessibilityLabel(scoreAccessibilityLabel)
                .allowsHitTesting(false)
        }
    }

    /// "Average 86 out of 100, 7 – 10am · Perfect" — "… for 7 – 11am" on a
    /// looked-at span.
    private var scoreAccessibilityLabel: String {
        let score = ringScore.map { "\(ringCaption) \($0) out of 100" } ?? "\(ringCaption), no score"
        if let span = lookedAtLabel, shownSpanScore != nil { return "\(score), for \(span)" }
        return "\(score), \(verdictLine.text)"
    }

    /// Report: verdict line + switch, the Range strip + integers, "Your
    /// hours 6 – 10am".
    private var reportColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: RethinkLayout.Grid.x2) {
                Text(verdictLine.text)
                    .scaledFont(size: Hero.verdictFont, weight: .semibold)
                    .foregroundStyle(verdictLine.tint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: RethinkLayout.Switch.height)
                    .accessibilityIdentifier("detail.verdictLine")
                Spacer(minLength: 0)
                HeroModeSwitch(mode: $heroMode)
            }
            reportStrip
                .padding(.top, Hero.headerToStrip)
            if let rangeLabel {
                Text("Your hours \(rangeLabel)")
                    .scaledFont(size: Hero.captionFont)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, Hero.numeralsToCaption)
                    .accessibilityIdentifier("detail.yourHours")
            }
        }
    }

    /// The Range strip (5pt, tier per hour) and its hour integers.
    @ViewBuilder
    private var reportStrip: some View {
        if let authored {
            let tiers = viewModel.rangeStripTiers(for: authored, dayIndex: selectedDayIndex, now: now())
            let slots = viewModel.rangeSlots(for: authored, dayIndex: selectedDayIndex)
            VStack(alignment: .leading, spacing: Hero.stripToNumerals) {
                HStack(spacing: RethinkLayout.Card.stripSegmentGap) {
                    ForEach(Array(tiers.enumerated()), id: \.offset) { _, tier in
                        RoundedRectangle(cornerRadius: Hero.stripHeight / 2, style: .continuous)
                            .fill(tier.map(Theme.tierColor) ?? Theme.timelineTrack)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Hero.stripHeight)
                StripIntegers(startLocalHour: slots.first?.localHour, count: tiers.count)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rangeLabel.map { "Hours \($0)" } ?? "Hours")
            .accessibilityIdentifier("detail.reportStrip")
        }
    }

    /// Explore: the switch on top, the `−` pills `+` row under it.
    private var exploreColumn: some View {
        VStack(alignment: .trailing, spacing: Hero.switchToPills) {
            HeroModeSwitch(mode: $heroMode)
            carouselRow
                .frame(height: Hero.stepDiameter)
                // Room for the Best hours bar under the pills.
                .padding(.bottom, Hero.pillsToBestBar + Hero.bestBarHeight)
        }
    }

    /// The green bar under the Best hours window's pills — only the part of
    /// the Window the row shows.
    @ViewBuilder
    private func bestBar(carousel: HourCarousel, pillWidth: CGFloat) -> some View {
        if let start = selectedDay?.startIndex, let end = selectedDay?.endIndex,
           selectedDay?.hasWindow == true {
            let span = carousel.span
            let lower = max(start, span.lowerBound)
            let upper = min(end, span.upperBound)
            if lower < upper {
                let pitch = pillWidth + Layout.pillGap
                RoundedRectangle(cornerRadius: Hero.bestBarHeight / 2, style: .continuous)
                    .fill(verdictLine.tint)
                    .frame(width: CGFloat(upper - lower) * pitch - Layout.pillGap,
                           height: Hero.bestBarHeight)
                    .offset(x: CGFloat(lower - span.lowerBound) * pitch)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Your hours / Best hours / Looking at — one 32pt row each; the
    /// highlighted row (what the ring and the cards describe) sits on the
    /// accent band, 12 / 8 inset.
    private var exploreRowsView: some View {
        VStack(spacing: 0) {
            ForEach(exploreRows) { row in
                HStack(spacing: 0) {
                    Text(row.label)
                        .scaledFont(size: Hero.rowFont)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(minWidth: Hero.valueColumn, alignment: .leading)
                    Text(row.value)
                        .scaledFont(size: Hero.rowFont)
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: RethinkLayout.Grid.x2)
                    Text(row.result)
                        .scaledFont(size: Hero.rowFont, weight: row.resultIsVerdict ? .semibold : .regular)
                        .foregroundStyle(row.resultIsVerdict ? Theme.ratingTint(row.resultRating)
                                                             : Theme.primaryText)
                        .contentTransition(.numericText())
                }
                .lineLimit(2)
                .padding(.horizontal, Hero.bandHorizontalInset)
                .padding(.vertical, RethinkLayout.Grid.x2)
                .frame(minHeight: Hero.rowHeight)
                .background {
                    if row.isHighlighted {
                        RoundedRectangle(cornerRadius: RethinkLayout.innerRadius, style: .continuous)
                            .fill(Theme.accentTint)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label), \(row.value), \(row.result)")
                .accessibilityAddTraits(row.isHighlighted ? .isSelected : [])
                .accessibilityIdentifier("detail.row.\(row.kind)")
            }
        }
        .animation(fade, value: exploreRows)
    }

    /// "Back to 6 – 10am" — full width, 36 tall, r8; springs the row home.
    private func backPill(_ range: String) -> some View {
        Button(action: returnToRange) {
            HStack(spacing: Hero.backGlyphToText) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: Hero.rowFont, weight: .semibold))
                Text(ExploreRows.backLabel(range: range))
                    .scaledFont(size: Hero.rowFont, weight: .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.accentBrand)
            .padding(.horizontal, RethinkLayout.Grid.x3)
            .frame(maxWidth: .infinity, minHeight: Hero.backHeight)
            .background(Theme.timelineTrack,
                        in: RoundedRectangle(cornerRadius: RethinkLayout.innerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(ExploreRows.backLabel(range: range))
        .accessibilityIdentifier("detail.backToRange")
    }

    // MARK: The looked-at span's score (server-side, existing call)

    /// How long the row must rest before the span is scored.
    private static let spanScoreDebounce: Duration = .milliseconds(350)

    /// One server call for the span on screen once it settles off the Range
    /// in Explore. The reply lands only if that span is still the one shown.
    private func scheduleSpanScore() {
        scoringTask?.cancel()
        guard heroMode == .explore, let carousel, !carousel.isAtRange,
              SpanScoring.showsButton(isAtRange: false, slots: displayedSlots),
              let key = spanKey, let authored else { return }
        scoringTask = Task { @MainActor in
            try? await Task.sleep(for: Self.spanScoreDebounce)
            guard !Task.isCancelled, key == spanKey else { return }
            let result = await viewModel.scoreSpan(for: authored, span: key.span)
            guard !Task.isCancelled, key == spanKey, let result else { return }
            withAnimation(fade) { scoredSpan = ScoredSpan(key: key, result: result) }
        }
    }

    /// The clearing rule's one place.
    private func clearSpanScore() {
        scoringTask?.cancel()
        scoringTask = nil
        scoredSpan = nil
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accentBrand)
                .opacity(enabled ? 1 : 0.35)
                .frame(width: RethinkLayout.Hero.stepDiameter, height: RethinkLayout.Hero.stepDiameter)
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
                .overlay(alignment: .bottomLeading) {
                    bestBar(carousel: carousel, pillWidth: pillWidth)
                        .offset(y: RethinkLayout.Hero.pillsToBestBar + RethinkLayout.Hero.bestBarHeight)
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
            // Read on the main actor, outside the Sendable transition closure.
            let reduceMotion = reduceMotion
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
        let shape = RoundedRectangle(cornerRadius: RethinkLayout.Hero.pillRadius, style: .continuous)
        return shape
            .fill(fill.opacity(passed ? (chosen ? 1 : 0.5) : 1))
            .overlay(
                Text(RangeStripAxis.numeral(viewModel.localHour(at: index) ?? 0))
                    .font(compact ? .system(size: 9, weight: .semibold)
                                  : .system(size: 11, weight: chosen ? .semibold : .medium))
                    .foregroundStyle(passed ? Theme.secondaryText : Theme.onGradient)
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
        scrollMarker.set(slot)
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

    /// Springs the row back onto the Range (the back pill, a ring tap, a
    /// switch to Report).
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
        // A chosen hour is judged only if it is a Range hour; the average
        // whenever the span overlaps the Range.
        let inRange = carousel?.overlapsRange ?? false
        let hour = displayedHour
        // Accessibility sizes: one column, so the scaled words have room.
        let columnCount = Layout.metricGridColumnCount(isAccessibilitySize: isStacked)
        let squareFloor = Layout.metricCardHasSquareFloor(columnCount: columnCount)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Layout.gridColumnGap),
                            count: columnCount)
        return LazyVGrid(columns: columns, spacing: Layout.gridRowGap) {
            ForEach(metrics, id: \.self) { metric in
                MetricCardView(metric: metric,
                               hour: hour,
                               threshold: authored?.thresholds[metric],
                               verdict: verdict(for: metric, hour: hour, inRange: inRange),
                               catalog: catalog,
                               windUnit: windUnit)
                    // Two columns: square at the default size, taller once
                    // the scaled text needs the room (never clipped). One
                    // column (AX sizes): the content's own height — a
                    // full-width square would be mostly empty.
                    .atLeastSquare(squareFloor)
            }
            // Last in the grid, the metric square's own geometry: opens the
            // editor on Metrics (build 10).
            if authored != nil,
               AddMetricTile.isOffered(displayMetrics: metrics, catalog: catalog) {
                AddMetricTile { openEditor(at: .metrics) }
                    .atLeastSquare(squareFloor)
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

    // MARK: The edit circles — Edit range / Edit metrics (owner rulings
    // 2026-11-04: the list card became two captioned circles on the ground)

    /// Two 44pt circles centred under the metric grid, 32pt apart, each with
    /// its caption 6pt below. Liquid Glass under iOS 26 (one container, like
    /// the − / + pieces), thin material + hairline below it.
    private var editCircles: some View {
        GlassGroup(spacing: Layout.editCircleBlend) {
            HStack(alignment: .top, spacing: Layout.editCircleGap) {
                editCircle(systemName: "clock",
                           caption: "Range",
                           label: "Edit range",
                           identifier: "detail.editRange",
                           liftTick: rangeLiftTick) {
                    rangeLiftTick += 1
                    openEditor(at: .range)
                }
                editCircle(systemName: "slider.horizontal.3",
                           caption: "Metrics",
                           label: "Edit metrics",
                           identifier: "detail.editMetrics",
                           liftTick: metricsLiftTick) {
                    metricsLiftTick += 1
                    openEditor(at: .metrics)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(authored == nil)
    }

    /// One circle + its caption as one button (the caption is part of the
    /// target and of the press). Touch-down = `PressStyle`; release = the
    /// shared lift (`liftOnRelease`) + the light impact, then the sheet.
    private func editCircle(systemName: String,
                            caption: String,
                            label: String,
                            identifier: String,
                            liftTick: Int,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Layout.editCircleToCaption) {
                Image(systemName: systemName)
                    .font(.system(size: Layout.editCircleGlyph, weight: .semibold))
                    .foregroundStyle(Theme.accentBrand)
                    .frame(width: Layout.editCircleDiameter, height: Layout.editCircleDiameter)
                    .glassPieceSurface(in: Circle(), enabled: true, fallback: .material)
                // The circle stays 44 (ruling 9a / HIG target); its caption
                // grows and may wrap, centred under it.
                Text(caption)
                    .scaledFont(size: Layout.editCaptionFont)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .liftOnRelease(trigger: liftTick)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }

    // MARK: Delete (build 10 — the editor's words, confirmed, then home)

    /// A quiet destructive text button at the foot of the page; the
    /// confirmation is the editor's own dialog. Confirming deletes from the
    /// store (the dashboard drops the card through the forecast cache with
    /// no POST) and pops to the dashboard via its navigation path — never
    /// `dismiss` (the pushed detail must not read it — XCUI hang).
    private var deleteButton: some View {
        Button(ActivityDeletionCopy.button, role: .destructive) {
            confirmingDelete = true
        }
        .scaledFont(size: 15, weight: .semibold)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .disabled(authored == nil)
        .accessibilityIdentifier("detail.delete")
        .confirmationDialog(ActivityDeletionCopy.title, isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button(ActivityDeletionCopy.confirm, role: .destructive) {
                viewModel.store.delete(id: activity.activityId)
                onActivityDeleted()
            }
            .accessibilityIdentifier("detail.confirmDelete")
        }
    }

    /// The light impact fires first, then the editor sheet opens on `step`.
    private func openEditor(at step: EditorStep) {
        guard let authored else { return }
        editTick += 1
        editing = EditRequest(activity: authored, step: step)
    }
}

// MARK: The programmatic-scroll marker (build-8 deferral 9)

/// Tells a programmatic scroll's arrival from a user scroll on the pill
/// row. Single-use: the FIRST `scrolledSlot` change after `set` consumes it
/// — the arrival (no selection haptic) or, when a user scroll interrupted
/// the animation, a user move. The marker never outlives that change, so a
/// later user scroll that happens to land on the old target still ticks.
struct ProgrammaticScrollMarker: Equatable {
    private(set) var target: Int?

    mutating func set(_ slot: Int) { target = slot }

    /// True when `new` is the programmatic arrival; always clears.
    mutating func consume(_ new: Int?) -> Bool {
        defer { target = nil }
        guard let target else { return false }
        return new == target
    }
}

// MARK: Liquid Glass — `GlassGroup`, `glassPieceSurface` and `glassCapsule`
// are shared with the dashboard (Glass.swift)

private extension View {
    /// The − / + piece's surface: a 32pt glass circle on the recess track.
    func stepPieceSurface(enabled: Bool) -> some View {
        glassPieceSurface(in: Circle(),
                          enabled: enabled,
                          fallback: .track)
    }
}

#if DEBUG
// The fixture forecast is 2026-06-19: the previews pin `now` to 4:30am Dubai that day (before every Range) so the pills draw their tier colours instead of passed-grey.
private let previewNow: @Sendable () -> Date = { ISO8601DateFormatter().date(from: "2026-06-19T00:30:00Z")! }

#Preview("Cycling (Perfect today)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[0],
                           viewModel: viewModel,
                           now: previewNow)
    }
    .task { await viewModel.loadForecast() }
}

#Preview("Cycling (Perfect today) — dark") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[0],
                           viewModel: viewModel,
                           now: previewNow)
    }
    .task { await viewModel.loadForecast() }
    .preferredColorScheme(.dark)
}

/// Four thresholded metrics → four cards (the grid is not capped at the
/// frames' three). `PreviewFixtures.cycling` carries temp/wind/rain/uV.
#Preview("Cycling (4 metrics)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[0],
                           viewModel: viewModel,
                           now: previewNow)
    }
    .task { await viewModel.loadForecast() }
}

#Preview("Running") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        // activities[2] — the fixture list is cycling / fishingLite / running.
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[2],
                           viewModel: viewModel,
                           now: previewNow)
    }
    .task { await viewModel.loadForecast() }
}

/// "Your range 6 – 9am · Time passed" (owner ruling 2026-11-04): `now` is
/// 10am Dubai on the fixture's day 0 (forecast 4am), after Running's 6–9am.
#Preview("Running (Time passed)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[2],
                           viewModel: viewModel,
                           now: { ISO8601DateFormatter().date(from: "2026-06-19T06:00:00Z")! })
    }
    .task { await viewModel.loadForecast() }
}

/// The "No Window" word, Regular 12 light red (owner ruling 2026-11-04):
/// the fixture rates Fishing Lite rating-null on day 0.
#Preview("Fishing Lite (No Window)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[1],
                           viewModel: viewModel,
                           now: previewNow)
    }
    .task { await viewModel.loadForecast() }
}

/// HIG check: the hero and cards at the accessibility XL text size — the
/// hero stacks (ring on top, the hour row block under it) and the metric
/// grid goes to one column.
#Preview("Cycling (Accessibility XL)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[0],
                           viewModel: viewModel,
                           now: previewNow)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
    .task { await viewModel.loadForecast() }
}

/// The UI test's size (`UICTContentSizeCategoryAccessibilityXXL`).
#Preview("Cycling (Accessibility XXL)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[0],
                           viewModel: viewModel,
                           now: previewNow)
    }
    .environment(\.dynamicTypeSize, .accessibility4)
    .task { await viewModel.loadForecast() }
}

/// The smallest text size: the hero keeps its side-by-side layout.
#Preview("Cycling (Extra Small)") {
    let viewModel = PreviewFixtures.dashboardViewModel()
    NavigationStack {
        ActivityDetailView(activity: PreviewFixtures.forecast.activities[0],
                           viewModel: viewModel,
                           now: previewNow)
    }
    .environment(\.dynamicTypeSize, .xSmall)
    .task { await viewModel.loadForecast() }
}
#endif

// MARK: The Report strip's integers

/// The hour integers under the Report strip, on the segment boundaries —
/// first left-aligned, last right-aligned, the rest centred (the card's
/// rule, thinned to what the width holds).
private struct StripIntegers: View {
    let startLocalHour: Int?
    let count: Int

    @ScaledMetric(relativeTo: .caption) private var slotHeight: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var halfWidth: CGFloat = 7

    var body: some View {
        if let startLocalHour, count > 0 {
            GeometryReader { geo in
                let labels = RangeStripAxis.labels(
                    startLocalHour: startLocalHour,
                    hourCount: count,
                    maxLabels: RangeStripAxis.maxLabels(fittingWidth: geo.size.width,
                                                        labelWidth: 2 * halfWidth))
                ForEach(labels, id: \.boundary) { label in
                    let fraction = CGFloat(label.boundary) / CGFloat(count)
                    let nudge: CGFloat = label.boundary == 0 ? halfWidth
                        : (label.boundary == count ? -halfWidth : 0)
                    Text(label.text)
                        .scaledFont(size: RethinkLayout.Card.numeralFont, weight: .medium)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                        .position(x: geo.size.width * fraction + nudge, y: slotHeight / 2)
                }
            }
            .frame(height: slotHeight)
        } else {
            Color.clear.frame(height: slotHeight)
        }
    }
}
