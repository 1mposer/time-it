import SwiftUI

/// Activity Detail v3 (Figma `456:358` / `464:2348`, owner-approved
/// 2026-09-30; day-jump `508:417`, owner-approved 2026-10-02; hero carousel —
/// depth & polish pass build 8, owner rulings 2026-10-31 / 2026-11-01 /
/// 2026-11-03 / 2026-11-04). Opens on TODAY. Top to bottom: the week-dot row
/// (the day-jump control — ring on the selected day), the hero (the 64pt
/// day-score ring + rating word, and beside it the hour row: `−` · a
/// natively scrolling strip of tier-coloured hour pills · `+`, and under it
/// row 1 — the fixed Range line — and, away from the Range, row 2 — the span
/// action row), square metric cards two per row AVERAGING the chosen hours,
/// then the two captioned edit circles — Range / Metrics (owner rulings
/// 2026-11-04; they replaced the list card).
///
/// The one-place rule (owner rulings 2026-11-04): the user's chosen Range
/// lives in exactly ONE place on the detail and never changes — row 1 always
/// reads "Your range 6 – 10am" (" · Time passed" once the shown day's whole
/// Range has ended), wherever the carousel is. It never names the span.
///
/// Hero wording (owner rulings 2026-11-04): a day with no rating reads
/// "No Window" under the ring in Regular 12 light red (`Theme.noWindowTint`)
/// — Perfect / Good stay Semibold in their tint.
///
/// The row always shows the FULL Range: hours of it before the forecast
/// start are drawn grey with no data. No Calculate button: the cards
/// recompute live as the row settles, the Range's home slots keep a faint
/// ghost outline while the span drifts, and the return button at row 1's end
/// (present only away from the Range) or a tap on the ring springs the row
/// home.
///
/// The hero ring shows the selected DAY's score (`days[selectedDayIndex]
/// .score` from the wire) — the ring, the rating word and the day selection
/// never move with the carousel, EXCEPT for a scored span (owner rulings
/// 2026-11-04): away from the Range, row 2's glass "Score 7 – 11am" capsule
/// asks the SERVER to score the shown hours (`DashboardViewModel.scoreSpan`
/// — no client formula); the ring then counts to that score, the word takes
/// the span's verdict, and the capsule becomes the quiet "Scored 7 – 11am" —
/// the one place the span is named (no caption under the word). The span
/// score is detail-only and cleared the moment the span, the day or the
/// forecast changes, so the ring shows the day score or the CURRENT span's,
/// never a stale span's; a new span brings the capsule back.
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
    /// The span whose score is in flight (its button is disabled, dimmed).
    @State private var scoringKey: SpanKey?
    /// The span whose score just failed — its row reads the failure note.
    @State private var failedKey: SpanKey?
    @State private var failureTask: Task<Void, Never>?
    /// Bumped on the score button's release: the lift animation (skipped
    /// under Reduce Motion) and the impact haptic (always).
    @State private var liftTick = 0
    @State private var scoreTick = 0
    /// The edit circles' own lift ticks (one each, so only the tapped circle
    /// lifts) and their shared impact haptic.
    @State private var rangeLiftTick = 0
    @State private var metricsLiftTick = 0
    @State private var editTick = 0
    /// The detail's Delete is awaiting its confirmation.
    @State private var confirmingDelete = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Accessibility sizes stack the hero and single-column the grid.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Dynamic Type (owner ruling 8): the text rows' heights scale with the
    // style their text scales with (`scaledFont`), from the Figma defaults.
    @ScaledMetric(relativeTo: .caption) private var wordHeight = Theme.Detail.wordHeight
    @ScaledMetric(relativeTo: .footnote) private var lineHeight = Theme.Detail.lineHeight
    @ScaledMetric(relativeTo: .footnote) private var spanRowHeight = Theme.Detail.spanRowHeight
    @ScaledMetric(relativeTo: .footnote) private var spanRowFont = Theme.Detail.spanRowFont
    @ScaledMetric(relativeTo: .footnote) private var spanCapsulePadding = Theme.Detail.spanCapsulePadding

    private typealias Layout = Theme.Detail

    /// The hero's text rows at the user's text size (`.standard` at default).
    private var heroMetrics: Layout.HeroMetrics {
        .scaled(wordHeight: wordHeight, lineHeight: lineHeight, spanRowHeight: spanRowHeight)
    }

    /// Ruling 5 (the surviving part): at accessibility sizes the hour
    /// cluster drops under the ring instead of squeezing beside it.
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

    /// Row 2 under the Range line: the score capsule, the quiet "Scored …"
    /// text once the shown span has a result, or for ~2 s after a failed
    /// call the note that takes the capsule's place.
    private enum SpanRow: Equatable {
        case button(WindowSpec)
        case scored(WindowSpec)
        case failure
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

    /// Row 1 under the pill row: always "Your range …" (with "· Time passed"
    /// once the whole Range has ended); away from the Range only the return
    /// button at its end appears. Derived from the same `carousel` as the
    /// cards, so the button comes and goes on the same settle. Nil without a
    /// Range.
    private var rangeLine: RangeLine? {
        guard let carousel, let range = carousel.rangeHours,
              let window = authored?.window, let deriver else { return nil }
        return RangeLine(window: window,
                         isAtRange: carousel.isAtRange,
                         rangeHasPassed: deriver.rangeHasPassed(range, now: now()))
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

    /// Row 2 exists only away from the Range: "Scored …" once the shown span
    /// has a result; otherwise the capsule on a span with a data hour (a
    /// failed call shows its note instead); nothing on an all-gone span.
    private var spanRow: SpanRow? {
        guard let carousel, !carousel.isAtRange, let key = spanKey else { return nil }
        if let shown = shownSpanScore { return .scored(shown.window) }
        guard let deriver,
              SpanScoring.showsButton(isAtRange: carousel.isAtRange, slots: displayedSlots),
              let window = SpanScoring.window(for: carousel.span, deriver: deriver) else { return nil }
        return failedKey == key ? .failure : .button(window)
    }

    /// The ring's score and verdict: the scored span's, else the day's.
    private var ringScore: Int? { shownSpanScore.map(\.score) ?? selectedDay?.score }
    private var ringRating: Rating? { shownSpanScore.map(\.rating) ?? selectedDay?.rating }

    /// Row 2's fade (its swaps and its coming and going) — a crossfade under
    /// Reduce Motion.
    private var fade: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.value
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
                    // A minute tick scoped to the hero (build-8 deferral 5):
                    // passed pills and "Time passed" grey on the minute, not
                    // only on the next re-render. Nothing faster — a
                    // constantly re-rendering pushed detail starves XCUI.
                    TimelineView(.everyMinute) { _ in
                        heroCard
                    }
                    metricGrid
                }
                editCircles
                    .padding(.top, Layout.editCirclesTop - Layout.dotsToHero)
                deleteButton
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
            if scrollMarker.consume(new) { return }
            guard let opening = openingCarousel, let old, let new,
                  opening.span(forScrollAnchor: old) != opening.span(forScrollAnchor: new) else { return }
            selectionTick += 1
        }
        // The clearing rule: a new span (a settle, − / +, a return), a day
        // jump or a refetch drops the span score and its failure note, and
        // the ring falls back to the day score.
        .onChange(of: spanKey) { _, _ in
            clearSpanScore()
        }
        .sensoryFeedback(.selection, trigger: selectionTick)
        .sensoryFeedback(.impact(weight: .light), trigger: homeTick)
        .sensoryFeedback(.impact(weight: .light), trigger: scoreTick)
        .sensoryFeedback(.impact(weight: .light), trigger: editTick)
        .navigationTitle(current.label)
        .navigationBarTitleDisplayMode(.inline)
        // The circles are the detail's edit doors (the card gear is gone —
        // owner ruling 2026-10-06 #2); the editor keeps its Delete too. A
        // Activity deleted there pops the detail as the sheet closes: `authored` reads the
        // store, so it is nil the moment the delete lands (no refetch wait).
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
    ///
    /// Row 1 is the fixed Range line (owner rulings 2026-11-04). Away from
    /// the Range, row 2 — the span action row (capsule / "Scored …" /
    /// failure note, one constant 28pt slot) — hangs `rowToLine` under it.
    /// Row 2 never moves the pill row (the finger is on it); the hero grows
    /// to the taller column instead.
    private var heroCard: some View {
        let line = rangeLine
        let hasLine = line != nil
        let row = hasLine ? spanRow : nil
        let hasSpanRow = row != nil
        let metrics = heroMetrics
        let stacked = isStacked
        // One layout switched in place (`AnyLayout`), so the pill row's
        // scroll view keeps its identity across a text-size change.
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Layout.ringToRow))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Layout.ringToRow))
        let height = stacked
            ? Layout.stackedHeroHeight(hasLine: hasLine, hasSpanRow: hasSpanRow, metrics: metrics)
            : Layout.heroHeight(hasLine: hasLine, hasSpanRow: hasSpanRow, metrics: metrics)
        return layout {
            ringButton
                .frame(maxWidth: stacked ? .infinity : nil)
            VStack(alignment: .leading, spacing: Layout.rowToLine) {
                carouselRow
                    .frame(height: Layout.pillHeight)
                if let line {
                    rangeLineView(line)
                        .frame(height: metrics.lineHeight)
                }
                if let row {
                    spanRowView(row)
                        .frame(height: metrics.spanRowHeight, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(.top, stacked ? 0 : Layout.rowColumnTop(hasLine: hasLine, metrics: metrics))
        }
        .frame(height: height - Layout.heroInset - Layout.heroBottom,
               alignment: .top)
        .animation(fade, value: row)
        .padding(EdgeInsets(top: Layout.heroInset, leading: Layout.heroInset,
                            bottom: Layout.heroBottom, trailing: Layout.heroInset))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.detailContainer)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .cardLift(cornerRadius: Theme.Radius.lg)
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
                ScoreRingView(score: ringScore,
                              tint: heroDimmed ? Theme.secondaryText : Theme.ratingTint(ringRating),
                              style: .hero)
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .disabled(!canReturn)
            .accessibilityHidden(true)
            ratingWord
                .fixedSize()
                .frame(height: heroMetrics.wordHeight)
        }
        // A floor, not a width: a scaled word may be wider than the ring.
        .frame(minWidth: Layout.ringDiameter)
        .frame(height: Layout.scaledRingColumnHeight(heroMetrics), alignment: .top)
        .overlay {
            Color.clear
                .accessibilityElement()
                .accessibilityIdentifier("detail.score")
                .accessibilityLabel(scoreAccessibilityLabel)
                .allowsHitTesting(false)
        }
    }

    /// The word under the ring: Perfect / Good Semibold 12 in their tint;
    /// no rating (nil or unknown) → "No Window" Regular 12 light red (owner
    /// ruling 2026-11-04). Same slot either way, so the hero height holds.
    /// A scored span's verdict takes the day's place.
    private var ratingWord: some View {
        let rating = ringRating
        let isRated = rating == .perfect || rating == .good
        return Text(Self.verdictText(rating))
            .scaledFont(size: 12, weight: isRated ? .semibold : .regular)
            .foregroundStyle(heroDimmed ? Theme.secondaryText
                             : (isRated ? Theme.ratingTint(rating) : Theme.noWindowTint))
    }

    /// Fresh-eyes 5a: an unscored previewed span dims the ring and word.
    private var heroDimmed: Bool {
        SpanScoring.dimsVerdict(isAtRange: carousel?.isAtRange ?? true,
                                spanScored: shownSpanScore != nil)
    }

    /// `Day.ratingDisplay`'s words for any verdict (the day's or a span's).
    private static func verdictText(_ rating: Rating?) -> String {
        Day(dayIndex: 0, rating: rating).ratingDisplay
    }

    /// Row 1: "Your range 6 – 10am" — 13pt secondary text that never changes
    /// with the carousel (a day jump to a different Range rolls it,
    /// `numericText`); away from the Range the return button fades in at the
    /// line's end.
    private func rangeLineView(_ line: RangeLine) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(line.text)
                .scaledFont(size: Layout.lineFont)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                .foregroundStyle(Theme.accentBrand)
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

    /// "Perfect, score 86 out of 100" — "… for 4 to 8pm" on a scored span.
    private var scoreAccessibilityLabel: String {
        SpanScoring.scoreAccessibilityLabel(verdict: Self.verdictText(ringRating),
                                            score: ringScore,
                                            span: shownSpanScore?.window)
    }

    // MARK: Span scoring — row 2, the span action row (owner rulings 2026-11-04)

    /// The three row-2 states overlap in one leading-aligned slot, each laid
    /// out 28pt tall with its leading edge on the column's left edge (the
    /// Range text's and the − piece's x), so a swap (capsule → "Scored …",
    /// capsule ↔ failure note) is a true crossfade with nothing shifting.
    private func spanRowView(_ row: SpanRow) -> some View {
        ZStack(alignment: .leading) {
            switch row {
            case .button(let window):
                spanScoreButton(window)
                    .transition(.opacity)
            case .scored(let window):
                Text(SpanScoring.scoredLabel(window))
                    .font(.system(size: spanRowFont))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: spanRowHeight, alignment: .leading)
                    .accessibilityIdentifier("detail.scoredSpan")
                    .transition(.opacity)
            case .failure:
                Text("Couldn\u{2019}t score \u{2014} try again")
                    .font(.system(size: spanRowFont))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: spanRowHeight, alignment: .leading)
                    .accessibilityIdentifier("detail.scoreError")
                    .transition(.opacity)
            }
        }
    }

    /// "Score 7 – 11am": a 28pt glass capsule (12pt side padding, 13pt
    /// Semibold tinted label), its hit area padded to the HIG 44pt. Its own
    /// glass container — the hero's wraps only the − / + row, and the
    /// capsule must never blend into those pieces. The hit padding is grown
    /// and given back (`padding` / `-padding`), so the LAID-OUT capsule is
    /// 28pt tall at the column's left edge. Touch-down = `PressStyle`;
    /// release = the shared lift (on the label, a render effect — the resting
    /// layout never moves) + the impact haptic + the request. No spinner: in
    /// flight it is disabled at 60%.
    private func spanScoreButton(_ window: WindowSpec) -> some View {
        let inFlight = scoringKey != nil && scoringKey == spanKey
        let hitPad = Layout.hitPad(forSpanRowHeight: spanRowHeight)
        return GlassGroup(spacing: Layout.spanCapsuleBlend) {
            Button(action: scoreSpan) {
                Text(SpanScoring.buttonLabel(window))
                    .minimumScaleFactor(0.7)
                    .glassCapsule(font: .system(size: spanRowFont, weight: .semibold),
                                  height: spanRowHeight,
                                  horizontalPadding: spanCapsulePadding,
                                  enabled: !inFlight)
                    .opacity(inFlight ? Layout.inFlightOpacity : 1)
                    .liftOnRelease(trigger: liftTick)
                    .padding(.vertical, hitPad)
                    .contentShape(Rectangle())
                    .padding(.vertical, -hitPad)
            }
            .buttonStyle(PressStyle())
            .disabled(inFlight)
            .accessibilityIdentifier("detail.scoreSpan")
            .accessibilityLabel(SpanScoring.buttonAccessibilityLabel(window))
        }
    }

    /// How long the failure note holds the button's place.
    private static let failureNoteSeconds: Double = 2

    /// The button's action: lift + haptic, then one server call for the span
    /// on screen. The reply lands only if that span is still the one shown.
    private func scoreSpan() {
        guard let key = spanKey, scoringKey != key, let authored else { return }
        scoreTick += 1
        liftTick += 1 // `liftOnRelease` skips the motion under Reduce Motion
        scoringKey = key
        failedKey = nil
        Task { @MainActor in
            let result = await viewModel.scoreSpan(for: authored, span: key.span)
            if scoringKey == key { scoringKey = nil }
            guard key == spanKey else { return }
            if let result {
                withAnimation(fade) { scoredSpan = ScoredSpan(key: key, result: result) }
            } else {
                showFailure(for: key)
            }
        }
    }

    /// "Couldn't score — try again" in the button's place for ~2 s.
    private func showFailure(for key: SpanKey) {
        failureTask?.cancel()
        withAnimation(fade) { failedKey = key }
        failureTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.failureNoteSeconds))
            guard !Task.isCancelled, failedKey == key else { return }
            withAnimation(fade) { failedKey = nil }
        }
    }

    /// The clearing rule's one place.
    private func clearSpanScore() {
        failureTask?.cancel()
        failureTask = nil
        scoredSpan = nil
        failedKey = nil
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
                .foregroundStyle(Theme.accentBrand)
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
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sm)
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
    /// The − / + piece's surface: an r6 glass piece on the recess track.
    func stepPieceSurface(enabled: Bool) -> some View {
        glassPieceSurface(in: RoundedRectangle(cornerRadius: Theme.Radius.sm),
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
