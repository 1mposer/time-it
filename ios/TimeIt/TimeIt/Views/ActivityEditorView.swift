import SwiftUI

/// The authoring wizard, used for both create and edit: a fixed 4-tab header
/// (Name & Icon → Metrics → Range → Review) over a switched content area —
/// no TabView, no swiping (gating makes swipe semantics ambiguous). Save
/// lives on the Review tab and stays disabled until the draft builds a valid
/// Activity — one invalid Activity would 400 the whole dashboard request
/// (ADR-0005 atomic validation), so an invalid one can never be saved.
struct ActivityEditorView: View {

    // MARK: - Dependencies & state

    private let isNew: Bool
    private let catalog: MetricCatalogProviding
    private let onSave: (AuthoredActivity) -> Void
    private let onDelete: (() -> Void)?
    /// The forecast hour the review pills read for the draft's Range (today,
    /// or tomorrow once today's Range has passed) — the pills must never sit
    /// gray when live data exists (owner ruling 2026-09-01). Nil closure or
    /// nil result → neutral name-only pills (no forecast to read).
    private let reviewRangeStartHour: ((WindowSpec) -> HourlyWeather?)?
    /// True when the draft's Range has already fully passed today — Save
    /// surfaces the "showing you tomorrow" alert before committing.
    private let rangeHasPassedToday: ((WindowSpec) -> Bool)?

    @State private var draft: ActivityDraft
    @State private var step: Int = 0
    /// §6: an untouched template prefill is NOT a confirmed Range. Seeded
    /// from the incoming activity's window; set by any wheel change and by
    /// the warn-and-proceed path.
    @State private var rangeConfirmed: Bool
    @State private var showingRangeWarning = false
    @State private var confirmingDelete = false
    /// The built Activity parked while the passed-range alert is up; saving
    /// completes from the alert's OK.
    @State private var pendingPassedRangeSave: AuthoredActivity?
    @State private var expandedCategories: Set<String>
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    init(existing: AuthoredActivity,
         isNew: Bool,
         catalog: MetricCatalogProviding = StaticMetricCatalog(),
         onSave: @escaping (AuthoredActivity) -> Void,
         onDelete: (() -> Void)? = nil,
         reviewRangeStartHour: ((WindowSpec) -> HourlyWeather?)? = nil,
         rangeHasPassedToday: ((WindowSpec) -> Bool)? = nil) {
        self.isNew = isNew
        self.catalog = catalog
        self.onSave = onSave
        self.onDelete = onDelete
        self.reviewRangeStartHour = reviewRangeStartHour
        self.rangeHasPassedToday = rangeHasPassedToday
        let draft = ActivityDraft(from: existing)
        _draft = State(initialValue: draft)
        _rangeConfirmed = State(initialValue: draft.hadWindow)
        // The category holding the current icon starts expanded; the sentinel
        // (from scratch) belongs to no category → all collapsed.
        _expandedCategories = State(initialValue:
            IconCatalog.category(containing: draft.iconSymbol).map { [$0.id] } ?? [])
    }

    // MARK: - Body

    /// One parse+validate pass per render — the wizard re-renders on every
    /// keystroke, so computing the result per consumer would triple the work.
    var body: some View {
        let buildResult = draft.result(against: catalog)
        VStack(spacing: 0) {
            EditorTabBar(current: step,
                         isComplete: { isComplete($0) },
                         isUnlocked: { isUnlocked($0) },
                         onTap: { tapTab($0) })
            Theme.divider
                .frame(height: 0.5)
            tabContent(buildResult)
        }
        .background(Theme.appBackground)
        .safeAreaInset(edge: .bottom) { bottomBar(buildResult) }
        .navigationTitle(isNew ? "New Activity" : "Edit Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("editor.cancel")
            }
        }
        .onChange(of: draft.startHour) { _, _ in confirmRange() }
        .onChange(of: draft.endHour) { _, _ in confirmRange() }
    }

    @ViewBuilder
    private func tabContent(_ buildResult: (activity: AuthoredActivity?, issues: [String])) -> some View {
        switch EditorStep(rawValue: step) ?? .nameIcon {
        case .nameIcon: nameIconTab
        case .metrics: metricsTab
        case .range: rangeTab
        case .review: reviewTab(buildResult)
        }
    }

    // MARK: - Step completion / gating (EditorStep owns the rules)

    private func isComplete(_ index: Int) -> Bool {
        guard let tab = EditorStep(rawValue: index) else { return false }
        return tab.isComplete(draft: draft, catalog: catalog, rangeConfirmed: rangeConfirmed)
    }

    private func isUnlocked(_ index: Int) -> Bool {
        guard let tab = EditorStep(rawValue: index) else { return false }
        return tab.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: rangeConfirmed)
    }

    private var rangeIsValid: Bool { draft.startHour != draft.endHour }

    private func tapTab(_ index: Int) {
        if index <= step {
            showingRangeWarning = false
            step = index
        } else if index == EditorStep.review.rawValue, rangeIsValid, !rangeConfirmed,
                  isComplete(EditorStep.nameIcon.rawValue), isComplete(EditorStep.metrics.rawValue) {
            // §6: tapping Review over a valid-but-unconfirmed range takes the
            // warn-then-proceed path (shown on the Range tab, under the
            // button) — warnThenProceed reads the warning flag to tell first
            // press from second, so it must not be cleared before this call.
            warnThenProceed()
        } else {
            showingRangeWarning = false
            if isUnlocked(index) { step = index }
            // Locked tab: no-op.
        }
    }

    private func confirmRange() {
        rangeConfirmed = true
        showingRangeWarning = false
    }

    /// First press surfaces the warning (jumping to the Range tab if needed);
    /// the second press proceeds and confirms the range.
    private func warnThenProceed() {
        if step == EditorStep.range.rawValue, showingRangeWarning {
            rangeConfirmed = true
            showingRangeWarning = false
            step = EditorStep.review.rawValue
        } else {
            step = EditorStep.range.rawValue
            showingRangeWarning = true
        }
    }

    // MARK: - Bottom primary button (§8)

    private func bottomBar(_ buildResult: (activity: AuthoredActivity?, issues: [String])) -> some View {
        VStack(spacing: 8) {
            if step == EditorStep.review.rawValue {
                Button("Save Activity") {
                    guard let activity = buildResult.activity else { return }
                    // A Range that already passed today still saves — but the
                    // user is told the card will show tomorrow's conditions.
                    if let window = activity.window,
                       rangeHasPassedToday?(window) == true {
                        pendingPassedRangeSave = activity
                    } else {
                        onSave(activity)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accentOrange)
                .frame(maxWidth: .infinity)
                .disabled(buildResult.activity == nil)
                .accessibilityIdentifier("editor.save")
                .alert("The time you set has already passed today",
                       isPresented: Binding(get: { pendingPassedRangeSave != nil },
                                            set: { if !$0 { pendingPassedRangeSave = nil } })) {
                    Button("OK") {
                        guard let activity = pendingPassedRangeSave else { return }
                        pendingPassedRangeSave = nil
                        onSave(activity)
                        dismiss()
                    }
                    .accessibilityIdentifier("editor.passedRangeOK")
                } message: {
                    Text("We're going to show you tomorrow's conditions.")
                }
            } else {
                Button("Next Step") { nextStep() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.accentOrange)
                    .frame(maxWidth: .infinity)
                    .disabled(!nextStepEnabled)
                    .accessibilityIdentifier("editor.nextStep")
            }
            if showingRangeWarning, step == EditorStep.range.rawValue {
                Text("Are you sure you want to proceed without adding a range?")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("editor.rangeWarning")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    /// Next Step dims while the current tab is incomplete — except the Range
    /// tab's warning path, where it stays enabled to drive warn-then-proceed.
    private var nextStepEnabled: Bool {
        if step == EditorStep.range.rawValue { return rangeIsValid }
        return isComplete(step)
    }

    private func nextStep() {
        if step == EditorStep.range.rawValue, !rangeConfirmed {
            warnThenProceed()
        } else {
            step = min(step + 1, EditorStep.review.rawValue)
        }
    }

    // MARK: - Tab 0 — Name & Icon (§3)

    /// An edited activity may carry an icon that predates the catalog tree —
    /// it renders in a "Current" slot so editing can never lose it.
    private var legacyIcon: String? {
        let icon = draft.iconSymbol
        guard icon != "questionmark.circle", !IconCatalog.allIcons.contains(icon) else { return nil }
        return icon
    }

    private var nameIconTab: some View {
        Form {
            Section("Name") {
                // The whole row must raise the keyboard, not just the text's
                // leading edge (device finding 2026-08-30).
                TextField("Cycling...", text: $draft.label)
                    .textInputAutocapitalization(.sentences)
                    .focused($nameFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { nameFocused = true }
                    .accessibilityIdentifier("editor.name")
            }
            Section("Icon") {
                if let legacyIcon {
                    HStack(spacing: 12) {
                        Text("Current")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryText)
                        iconButton(legacyIcon)
                        Spacer()
                    }
                }
                OutlineGroup(IconCatalog.tree, children: \.children) { category in
                    DisclosureGroup(isExpanded: isExpandedBinding(category.id)) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5),
                                  spacing: 12) {
                            ForEach(category.icons, id: \.self) { symbol in
                                iconButton(symbol)
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Text(category.name)
                            .foregroundStyle(Theme.primaryText)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func isExpandedBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { expandedCategories.contains(id) },
                set: { expanded in
                    if expanded { expandedCategories.insert(id) } else { expandedCategories.remove(id) }
                })
    }

    private func iconButton(_ symbol: String) -> some View {
        Button {
            draft.iconSymbol = symbol
        } label: {
            ActivityIconView(identifier: symbol, size: 18)
                .foregroundStyle(draft.iconSymbol == symbol ? Color.white : Theme.primaryText.opacity(0.75))
                .frame(width: 40, height: 40)
                .background(draft.iconSymbol == symbol ? Theme.accentOrange : Theme.appBackground,
                            in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("icon.\(symbol)")
        .accessibilityLabel(symbol)
    }

    // MARK: - Tab 1 — Metrics (merged thresholds, §4)

    private var metricsTab: some View {
        Form {
            Section {
                DidYouKnowBox(key: "metricModes",
                              body: "If 'Priority' is selected for a metric, it will be considered more in the calculation.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(catalog.metrics) { descriptor in
                    metricRow(descriptor)
                }
            } footer: {
                Text("First three metrics show as chips on the card.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// Collapsed = icon + name. Tapping the header selects AND expands with a
    /// preset Must-have threshold (§4 — zero typing); tapping again deselects
    /// and discards. `moon` (displayOnly) selects but never expands;
    /// `dustAlert` (flag) expands to the mode menu only.
    @ViewBuilder
    private func metricRow(_ descriptor: MetricDescriptor) -> some View {
        let selected = draft.isSelected(descriptor.key)
        Button {
            if selected {
                draft.toggleMetric(descriptor.key)
            } else {
                draft.selectWithPreset(descriptor)
            }
        } label: {
            HStack(spacing: 10) {
                ActivityIconView(identifier: descriptor.iconSymbol, size: 15)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 22)
                Text(descriptor.displayName)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentOrange)
                }
            }
        }
        .accessibilityIdentifier("metric.\(descriptor.key)")

        if selected, descriptor.isThresholdable {
            if descriptor.kind == .numeric, draft.thresholds[descriptor.key] != nil {
                ThresholdSlider(descriptor: descriptor,
                                minText: boundText(descriptor.key, \.minText),
                                maxText: boundText(descriptor.key, \.maxText))
            }
            modeCheckboxes(descriptor)
        }
    }

    /// The two-checkbox mode row
    ///                      '   Priority: ☐                                 Show only: ☐    '
    /// Semantics live in
    /// `ThresholdCheckboxes`.
    private func modeCheckboxes(_ descriptor: MetricDescriptor) -> some View {
        VStack(
                alignment: .leading, spacing: 4) {
            checkbox("Priority:",
                     checked: ThresholdCheckboxes.isPriority(for: descriptor.key, in: draft),
                     identifier: "editor.priority.\(descriptor.key)") {
                ThresholdCheckboxes.togglePriority(for: descriptor, in: &draft)
            }
            Text("  ")
                .foregroundStyle(Theme.secondaryText)
            checkbox("Show only:",
                     checked: ThresholdCheckboxes.isShowOnly(for: descriptor.key, in: draft),
                     identifier: "editor.showOnly.\(descriptor.key)") {
                ThresholdCheckboxes.toggleShowOnly(for: descriptor, in: &draft)
            }
            Spacer(minLength: 10)
        }
    }

    private func checkbox(_ title: String, checked: Bool, identifier: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 80, alignment: .leading)
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(checked ? Theme.accentOrange : Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    /// Binding into one bound's text of the metric's threshold. The rows only
    /// render while the entry exists; the fallback covers the removal frame.
    private func boundText(_ key: String, _ path: WritableKeyPath<ThresholdDraft, String>) -> Binding<String> {
        Binding(get: { draft.thresholds[key]?[keyPath: path] ?? "" },
                set: { draft.thresholds[key]?[keyPath: path] = $0 })
    }

    // MARK: - Tab 2 — Range (§6)

    /// From and To are distinct boxes — one Form section each, so they render
    /// as separate spaced cards (owner edit 2026-08-30).
    private var rangeTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From:")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    hourWheel(selection: $draft.startHour, identifier: "editor.startHour")
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To:")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    hourWheel(selection: $draft.endHour, identifier: "editor.endHour")
                }
            }
            if draft.startHour == draft.endHour {
                Section {
                    Text("Start and end can't be the same.")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func hourWheel(selection: Binding<Int>, identifier: String) -> some View {
        Picker("", selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                Text(Self.hourText(hour)).tag(hour)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 120)
        .clipped()
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Tab 3 — Review (§7)

    private func reviewTab(_ buildResult: (activity: AuthoredActivity?, issues: [String])) -> some View {
        Form {
            Section {
                reviewCard
                    .accessibilityIdentifier("editor.reviewCard")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            footer:
            {
                Text("This is how your activity will look on the home screen.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .padding(.top, 10)
            }
            if !buildResult.issues.isEmpty {
                Section {
                    ForEach(buildResult.issues, id: \.self) { issue in
                        Text(issue)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }
            }
            if !isNew, onDelete != nil {
                deleteSection
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Review card

    /// The actual dashboard card as a representative preview (owner edit
    /// 2026-08-30): real icon, name, range chip, and metric chips from the
    /// draft; the timeline slice and its green are illustrative — a real
    /// rating exists only after the first fetch — but the metric pills read
    /// live forecast values when the dashboard has them (owner ruling
    /// 2026-09-01: pills never sit gray over live data). The fixed
    /// UTC-midnight deriver makes hour index == clock hour, so the draft's
    /// Range maps straight onto the axis.
    private var reviewCard: some View {
        let wrapped = draft.startHour > draft.endHour
        let endExclusive = wrapped ? draft.endHour + 24 : draft.endHour
        let duration = max(endExclusive - draft.startHour, 1)
        let day = Day(dayIndex: 0, rating: "perfect",
                      startIndex: draft.startHour,
                      endIndex: draft.startHour + duration,
                      duration: duration)
        let rating = ActivityRating(activityId: draft.id,
                                    label: ActivityDraft.finalLabel(draft.label),
                                    displayMetrics: draft.metrics,
                                    days: [day])
        let window = WindowSpec(startHour: draft.startHour, endHour: draft.endHour)
        return ActivityCardView(activity: rating,
                                day: day,
                                windowStartHour: reviewRangeStartHour?(window),
                                deriver: TimeDeriver(forecastStart: "2026-06-01T00:00:00Z",
                                                     timezone: "UTC"),
                                hoursCount: max(24, draft.startHour + duration),
                                iconSymbol: draft.iconSymbol,
                                isNocturnal: wrapped,
                                rangeChipLabel: RangeText.chipLabel(WindowSpec(startHour: draft.startHour,
                                                                              endHour: draft.endHour)),
                                sliceRange: draft.startHour..<(draft.startHour + duration),
                                tiers: Array(repeating: .green, count: duration),
                                catalog: catalog)
    }

    // MARK: - Delete (edit mode only)

    private var deleteSection: some View {
        Section {
            Button("Delete Activity", role: .destructive) {
                confirmingDelete = true
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("editor.delete")
            .confirmationDialog("Delete this activity?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                .accessibilityIdentifier("editor.confirmDelete")
            }
        }
    }

    // MARK: - Helpers

    /// "12am", "1am" … "11pm" — the shared clock dialect (RangeText).
    static func hourText(_ hour: Int) -> String {
        RangeText.hourText(hour)
    }
}

// MARK: - Tab header (§2)

/// The fixed 4-segment capsule header. States: current (accent fill),
/// complete (perfectGreen outline + checkmark — live validity, never
/// "visited"), incomplete (neutral gray, never red), locked (dimmed).
private struct EditorTabBar: View {
    let current: Int
    let isComplete: (Int) -> Bool
    let isUnlocked: (Int) -> Bool
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(EditorStep.allCases, id: \.rawValue) { tab in
                segment(tab)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func segment(_ tab: EditorStep) -> some View {
        let index = tab.rawValue
        let isCurrent = index == current
        let complete = isComplete(index)
        let locked = !isUnlocked(index) && index > current
        return Button {
            onTap(index)
        } label: {
            HStack(spacing: 4) {
                if complete, !isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(foreground(isCurrent: isCurrent, complete: complete))
            .background {
                if isCurrent {
                    Capsule().fill(Theme.accentOrange)
                } else {
                    Capsule().strokeBorder(border(complete: complete))
                }
            }
            .opacity(locked ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editor.tab.\(index)")
    }

    private func foreground(isCurrent: Bool, complete: Bool) -> Color {
        if isCurrent { return .white }
        return complete ? Theme.perfectGreen : Theme.secondaryText
    }

    private func border(complete: Bool) -> Color {
        complete ? Theme.perfectGreen : Theme.secondaryText.opacity(0.4)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("New (scratch)") {
    NavigationStack {
        ActivityEditorView(existing: .blank(),
                           isNew: true,
                           onSave: { _ in })
    }
}

#Preview("Edit (existing)") {
    NavigationStack {
        ActivityEditorView(existing: PreviewFixtures.cycling,
                           isNew: false,
                           onSave: { _ in },
                           onDelete: {})
    }
}
#endif
