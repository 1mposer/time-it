import SwiftUI

/// The authoring wizard, used for both create and edit (owner rulings
/// 2026-11-11, Lane A item 4; Figma `A/R2/Final` + `A/R3`): five steps —
/// Name → Metrics → Priority → Range → Review — walked with a glass Back and
/// a tinted-glass Next under a progress bar that never starts at zero. No tab
/// strip, no Form (the "settings list feel" the owner is escaping): opaque
/// cards and tiles on the ground, every floating control Liquid Glass. Save
/// lives on Review and stays disabled until the draft builds a valid
/// Activity — one invalid Activity would 400 the whole dashboard request
/// (ADR-0005 atomic validation).
struct ActivityEditorView: View {

    // MARK: - Dependencies & state

    private let isNew: Bool
    /// The very first Activity the user creates — the Review title says so.
    private let isFirstActivity: Bool
    private let catalog: MetricCatalogProviding
    private let onSave: (AuthoredActivity) -> Void
    private let onDelete: (() -> Void)?
    /// The Review reveal's computed card (the real score and colours);
    /// nil closure or nil result → the empty-ring card.
    private let reviewPreview: ((AuthoredActivity) async -> ReviewPreview?)?
    /// True when the draft's Range has already fully passed today — Save
    /// surfaces the "those hours have passed" alert before committing (the
    /// card is today-only since 2026-10-02; tomorrow lives in the week dots).
    private let rangeHasPassedToday: ((WindowSpec) -> Bool)?
    /// Wind-speed display unit for the slider (#26); the draft's bounds stay
    /// km/h.
    private let windUnit: WindSpeedUnit

    @State private var draft: ActivityDraft
    @State private var step: EditorStep
    /// An untouched prefill is NOT a confirmed Range. Seeded from the
    /// incoming activity's window; set by any wheel change and by the
    /// warn-and-proceed path.
    @State private var rangeConfirmed: Bool
    @State private var showingRangeWarning = false
    @State private var confirmingDelete = false
    /// The built Activity parked while the passed-range alert is up; saving
    /// completes from the alert's OK.
    @State private var pendingPassedRangeSave: AuthoredActivity?
    @State private var expandedCategories: Set<String>
    @State private var preview: ReviewPreview?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let sideMargin: CGFloat = 16
    static let topControl: CGFloat = 40
    static let primaryHeight: CGFloat = 50

    // MARK: - Init

    /// `initialStep`: the step to open on — the detail screen's Edit range /
    /// Edit metrics doors land on their own step (#25); everything else
    /// starts at Name. Resolved through `EditorStep.landingStep`, so a locked
    /// request can never open a gated step.
    init(existing: AuthoredActivity,
         isNew: Bool,
         isFirstActivity: Bool = false,
         initialStep: EditorStep = .nameIcon,
         catalog: MetricCatalogProviding = StaticMetricCatalog(),
         windUnit: WindSpeedUnit = .kmh,
         onSave: @escaping (AuthoredActivity) -> Void,
         onDelete: (() -> Void)? = nil,
         reviewPreview: ((AuthoredActivity) async -> ReviewPreview?)? = nil,
         rangeHasPassedToday: ((WindowSpec) -> Bool)? = nil) {
        self.isNew = isNew
        self.isFirstActivity = isFirstActivity
        self.catalog = catalog
        self.windUnit = windUnit
        self.onSave = onSave
        self.onDelete = onDelete
        self.reviewPreview = reviewPreview
        self.rangeHasPassedToday = rangeHasPassedToday
        var draft = ActivityDraft(from: existing)
        // "Show only" is retired (owner ruling 4a): a judged metric left
        // without a threshold gets its preset, not prioritised, on open.
        draft.adoptShowOnlyMetrics(catalog: catalog)
        _draft = State(initialValue: draft)
        _rangeConfirmed = State(initialValue: draft.hadWindow)
        _step = State(initialValue: EditorStep.landingStep(requested: initialStep, draft: draft,
                                                           catalog: catalog,
                                                           rangeConfirmed: draft.hadWindow))
        // The category holding the current icon starts expanded; the sentinel
        // (from scratch) opens the first category.
        _expandedCategories = State(initialValue:
            [IconCatalog.category(containing: draft.iconSymbol)?.id ?? IconCatalog.tree.first?.id ?? ""])
    }

    // MARK: - Body

    /// One parse+validate pass per render — the wizard re-renders on every
    /// keystroke, so computing the result per consumer would triple the work.
    var body: some View {
        let buildResult = draft.result(against: catalog)
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                ScrollView {
                    stepContent(buildResult, availableHeight: geo.size.height)
                        .padding(.horizontal, Self.sideMargin)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Theme.appBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar(buildResult) }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: draft.startHour) { _, _ in confirmRange() }
        .onChange(of: draft.endHour) { _, _ in confirmRange() }
        .task(id: step) {
            guard step == .review, let activity = buildResult.activity, let reviewPreview else { return }
            preview = await reviewPreview(activity)
        }
    }

    // MARK: - Top bar: glass Back · progress · glass ✕

    private var topBar: some View {
        HStack(spacing: 12) {
            if step != .nameIcon {
                glassCircle(symbol: "chevron.left", identifier: "editor.back", label: "Back") { goBack() }
                    .transition(.opacity)
            }
            EditorProgressBar(fraction: WizardProgress.fraction(for: step))
            glassCircle(symbol: "xmark", identifier: "editor.cancel", label: "Cancel") { dismiss() }
        }
        .padding(.horizontal, Self.sideMargin)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .animation(reduceMotion ? nil : EditorProgressBar.advance, value: step)
    }

    private func glassCircle(symbol: String, identifier: String, label: String,
                             action: @escaping () -> Void) -> some View {
        GlassControl(identifier: identifier, accessibilityLabel: label, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: Self.topControl, height: Self.topControl)
                .glassPieceSurface(in: Circle(), enabled: true, fallback: .material)
                .padding(2)
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private func stepContent(_ buildResult: (activity: AuthoredActivity?, issues: [String]),
                             availableHeight: CGFloat) -> some View {
        if step == .review {
            reviewStep(buildResult, availableHeight: availableHeight)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if let heading = step.heading {
                    Text(heading)
                        .scaledFont(size: 28, weight: .semibold)
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityAddTraits(.isHeader)
                }
                switch step {
                case .nameIcon: nameStep
                case .metrics: metricsStep
                case .priority: priorityStep
                case .range: rangeStep
                case .review: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Navigation

    private var rangeIsValid: Bool { draft.startHour != draft.endHour }

    private func goBack() {
        showingRangeWarning = false
        guard let previous = EditorStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func nextStep() {
        if step == .range, !rangeConfirmed {
            warnThenProceed()
        } else if let next = EditorStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    private func confirmRange() {
        rangeConfirmed = true
        showingRangeWarning = false
    }

    /// First press surfaces the warning; the second proceeds and confirms
    /// the range (an untouched prefill is not a confirmed Range).
    private func warnThenProceed() {
        if showingRangeWarning {
            rangeConfirmed = true
            showingRangeWarning = false
            step = .review
        } else {
            showingRangeWarning = true
        }
    }

    /// Next dims while the current step is incomplete — except on Range,
    /// where it stays enabled to drive warn-then-proceed.
    private var nextStepEnabled: Bool {
        if step == .range { return rangeIsValid }
        return step.isComplete(draft: draft, catalog: catalog, rangeConfirmed: rangeConfirmed)
    }

    // MARK: - Bottom: the tinted-glass primary action

    private func bottomBar(_ buildResult: (activity: AuthoredActivity?, issues: [String])) -> some View {
        VStack(spacing: 8) {
            if showingRangeWarning, step == .range {
                Text("Are you sure you want to proceed without choosing hours?")
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("editor.rangeWarning")
            }
            if step == .review {
                primaryButton("Save Activity", identifier: "editor.save",
                              enabled: buildResult.activity != nil) { save(buildResult.activity) }
                    .alert("Those hours have passed for today",
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
                        Text("Your card stays on today until midnight. Tomorrow is in the week dots.")
                    }
            } else {
                primaryButton("Next", identifier: "editor.nextStep", enabled: nextStepEnabled) { nextStep() }
            }
        }
        .padding(.horizontal, Self.sideMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func primaryButton(_ title: String, identifier: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        GlassGroup(spacing: 0) {
            Button(action: action) {
                Text(title)
                    .scaledFont(size: 17, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    // 50 at every regular size; at accessibility sizes the
                    // capsule grows with its label instead of clipping it
                    // (build-9 addendum new #8).
                    .padding(.vertical, 8)
                    .frame(minHeight: Self.primaryHeight)
                    .contentShape(Capsule())
            }
            .buttonStyle(PrimaryGlassButtonStyle())
            .disabled(!enabled)
            .accessibilityIdentifier(identifier)
        }
    }

    private func save(_ activity: AuthoredActivity?) {
        guard let activity else { return }
        // A Range that already passed today still saves — but the user is
        // told the card stays on today and tomorrow is in the week dots.
        if let window = activity.window, rangeHasPassedToday?(window) == true {
            pendingPassedRangeSave = activity
        } else {
            onSave(activity)
            dismiss()
        }
    }

    // MARK: - Step 1 — Name

    /// An edited activity may carry an icon that predates the catalog tree —
    /// it renders in a "Current" slot so editing can never lose it.
    private var legacyIcon: String? {
        let icon = draft.iconSymbol
        guard icon != "questionmark.circle", !IconCatalog.allIcons.contains(icon) else { return nil }
        return icon
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryText)
                // The whole card raises the keyboard, not just the text's
                // leading edge (device finding 2026-08-30).
                TextField("Cycling...", text: $draft.label)
                    .scaledFont(size: 17)
                    .textInputAutocapitalization(.sentences)
                    .focused($nameFocused)
                    .accessibilityIdentifier("editor.name")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .cardLift(cornerRadius: 16, light: .rest)
            .contentShape(Rectangle())
            .onTapGesture { nameFocused = true }

            if let legacyIcon {
                iconCard(title: "Current", icons: [legacyIcon], collapsible: false)
            }
            ForEach(IconCatalog.tree) { category in
                iconCard(title: category.name, icons: IconCatalog.flatten([category]), collapsible: true)
            }
        }
    }

    private func iconCard(title: String, icons: [String], collapsible: Bool) -> some View {
        let expanded = !collapsible || expandedCategories.contains(title)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                guard collapsible else { return }
                withAnimation(reduceMotion ? nil : MetricTile.selectSpring) {
                    if expanded { expandedCategories.remove(title) } else { expandedCategories.insert(title) }
                }
            } label: {
                HStack {
                    Text(title)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 0)
                    if collapsible {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            if expanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(icons, id: \.self) { symbol in iconButton(symbol) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .cardLift(cornerRadius: 16, light: .rest)
    }

    private func iconButton(_ symbol: String) -> some View {
        let selected = draft.iconSymbol == symbol
        return Button {
            draft.iconSymbol = symbol
        } label: {
            ActivityIconView(identifier: symbol, size: 20)
                .foregroundStyle(selected ? Theme.accentBrand : Theme.primaryText.opacity(0.75))
                .frame(width: 48, height: 48)
                .background(selected ? Theme.accentTint : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.accentBrand, lineWidth: MetricTile.ringWidth)
                    }
                }
                .symbolEffect(.bounce, value: selected)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("icon.\(symbol)")
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Step 2 — Metrics

    /// The grid, and under it the two-metric gate's one hint line while the
    /// gate is unmet (the Priority step's gate-line pattern).
    private var metricsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            MetricTileGrid(draft: $draft, catalog: catalog, windUnit: windUnit)
            if !MetricsGate.isMet(draft: draft) {
                Text(MetricsGate.hint)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("editor.metricsGate")
            }
        }
    }

    // MARK: - Step 3 — Priority

    private var priorityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(PriorityChoice.explainer)
                .scaledFont(size: 15)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("editor.priorityExplainer")
            PriorityStepView(draft: $draft, catalog: catalog)
            if !PriorityChoice.gateIsMet(draft: draft) {
                Text(PriorityChoice.gateHint)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("editor.priorityGate")
            }
        }
    }

    // MARK: - Step 4 — Range (two wheels in opaque cards)

    private var rangeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                wheelCard("From", selection: $draft.startHour, identifier: "editor.startHour")
                wheelCard("To", selection: $draft.endHour, identifier: "editor.endHour")
            }
            if draft.startHour == draft.endHour {
                Text("Start and end can't be the same.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.accentDestructive)
            }
        }
    }

    private func wheelCard(_ title: String, selection: Binding<Int>, identifier: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Theme.secondaryText)
            Picker(title, selection: selection) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(Self.hourText(hour)).tag(hour)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            .clipped()
            .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .cardLift(cornerRadius: 16, light: .rest)
    }

    // MARK: - Step 5 — Review (the reveal)

    private func reviewStep(_ buildResult: (activity: AuthoredActivity?, issues: [String]),
                            availableHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ReviewRevealView(title: reviewTitle,
                             line: Self.reviewLine(isNew: isNew, label: ActivityDraft.finalLabel(draft.label)),
                             draftRating: draftRating,
                             iconSymbol: draft.iconSymbol,
                             rangeChipLabel: RangeText.chipLabel(window),
                             rangeHourCount: rangeHourCount,
                             stripStartLocalHour: draft.startHour,
                             preview: preview)
            if !buildResult.issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(buildResult.issues, id: \.self) { issue in
                        Text(issue)
                            .scaledFont(size: 13)
                            .foregroundStyle(Theme.accentDestructive)
                    }
                }
            }
            Spacer(minLength: 0)
            if !isNew, onDelete != nil { deleteButton }
        }
        .frame(maxWidth: .infinity, minHeight: max(availableHeight - 36, 0))
    }

    private var reviewTitle: String {
        Self.reviewTitle(isNew: isNew, isFirstActivity: isFirstActivity)
    }

    /// The Review reveal's title (fresh-eyes row 9a, owner 2026-11-12):
    /// nothing is created before Save, so a new Activity is "Your first" /
    /// "Your new activity"; an edit keeps "Your activity".
    static func reviewTitle(isNew: Bool, isFirstActivity: Bool) -> String {
        guard isNew else { return "Your activity" }
        return isFirstActivity ? "Your first activity" : "Your new activity"
    }

    /// The line under the reveal's card (row 9a): a new Activity reaches the
    /// dashboard on Save; an edited one is already there.
    static func reviewLine(isNew: Bool, label: String) -> String {
        isNew ? "Save to add it to your dashboard." : "\(label) is on your dashboard."
    }

    private var window: WindowSpec { WindowSpec(startHour: draft.startHour, endHour: draft.endHour) }

    private var rangeHourCount: Int {
        let end = draft.startHour > draft.endHour ? draft.endHour + 24 : draft.endHour
        return max(end - draft.startHour, 1)
    }

    /// The card's identity before the server answers: no days, so the ring
    /// is empty and the strip grey (never a fake verdict).
    private var draftRating: ActivityRating {
        ActivityRating(activityId: draft.id,
                       label: ActivityDraft.finalLabel(draft.label),
                       displayMetrics: draft.metrics,
                       days: [])
    }

    private var deleteButton: some View {
        Button("Delete Activity", role: .destructive) {
            confirmingDelete = true
        }
        .scaledFont(size: 15, weight: .semibold)
        .frame(minHeight: 44)
        .accessibilityIdentifier("editor.delete")
        .confirmationDialog("Delete this activity?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete?()
                dismiss()
            }
            .accessibilityIdentifier("editor.confirmDelete")
        }
    }

    // MARK: - Helpers

    /// "12am", "1am" … "11pm" — the shared clock dialect (RangeText).
    static func hourText(_ hour: Int) -> String {
        RangeText.hourText(hour)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("New (scratch)") {
    NavigationStack {
        ActivityEditorView(existing: .blank(), isNew: true, isFirstActivity: true, onSave: { _ in })
    }
}

#Preview("Edit (existing)") {
    NavigationStack {
        ActivityEditorView(existing: PreviewFixtures.cycling, isNew: false,
                           onSave: { _ in }, onDelete: {})
    }
}
#endif
