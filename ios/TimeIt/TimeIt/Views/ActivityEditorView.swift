import SwiftUI

/// The authoring wizard, used for both create and edit: a fixed 4-tab header
/// (Name & Icon → Metrics → Range → Review) over a switched content area —
/// no TabView, no swiping (gating makes swipe semantics ambiguous). Save
/// lives on the Review tab and stays disabled until the draft builds a valid
/// Activity — one invalid Activity would 400 the whole dashboard request
/// (ADR-0005 atomic validation), so an invalid one can never be saved.
struct ActivityEditorView: View {
    private let isNew: Bool
    private let catalog: MetricCatalogProviding
    private let onSave: (AuthoredActivity) -> Void
    private let onDelete: (() -> Void)?

    @State private var draft: ActivityDraft
    @State private var step: Int = 0
    /// §6: an untouched template prefill is NOT a confirmed Range. Seeded
    /// from the incoming activity's window; set by any wheel change and by
    /// the warn-and-proceed path.
    @State private var rangeConfirmed: Bool
    @State private var showingRangeWarning = false
    @State private var confirmingDelete = false
    @State private var expandedCategories: Set<String>
    @Environment(\.dismiss) private var dismiss

    init(existing: AuthoredActivity,
         isNew: Bool,
         catalog: MetricCatalogProviding = StaticMetricCatalog(),
         onSave: @escaping (AuthoredActivity) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.isNew = isNew
        self.catalog = catalog
        self.onSave = onSave
        self.onDelete = onDelete
        let draft = ActivityDraft(from: existing)
        _draft = State(initialValue: draft)
        _rangeConfirmed = State(initialValue: draft.hadWindow)
        // The category holding the current icon starts expanded; the sentinel
        // (from scratch) belongs to no category → all collapsed.
        _expandedCategories = State(initialValue:
            IconCatalog.category(containing: draft.iconSymbol).map { [$0.id] } ?? [])
    }

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

    // MARK: step completion / gating (EditorStep owns the rules)

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

    // MARK: bottom primary button (§8)

    private func bottomBar(_ buildResult: (activity: AuthoredActivity?, issues: [String])) -> some View {
        VStack(spacing: 8) {
            if step == EditorStep.review.rawValue {
                Button("Save Activity") {
                    guard let activity = buildResult.activity else { return }
                    onSave(activity)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accentOrange)
                .frame(maxWidth: .infinity)
                .disabled(buildResult.activity == nil)
                .accessibilityIdentifier("editor.save")
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

    // MARK: tab 0 — Name & Icon (§3)

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
                TextField("Cycling...", text: $draft.label)
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

    // MARK: tab 1 — Metrics (merged thresholds, §4)

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
            modeMenu(descriptor)
        }
    }

    /// The 3-way mode control (§4) — replaces the required-toggle and the
    /// Add/Remove-threshold rows.
    private func modeMenu(_ descriptor: MetricDescriptor) -> some View {
        let current = ThresholdMode.current(for: descriptor.key, in: draft)
        return ControlGroup {
            ForEach(ThresholdMode.allCases, id: \.self) { mode in
                Button(mode.label) {
                    mode.apply(for: descriptor, to: &draft)
                }
            }
        } label: {
            Label(current.label, systemImage: "slider.horizontal.3")
        }
        .controlGroupStyle(.compactMenu)
        .accessibilityIdentifier("editor.mode.\(descriptor.key)")
    }

    /// Binding into one bound's text of the metric's threshold. The rows only
    /// render while the entry exists; the fallback covers the removal frame.
    private func boundText(_ key: String, _ path: WritableKeyPath<ThresholdDraft, String>) -> Binding<String> {
        Binding(get: { draft.thresholds[key]?[keyPath: path] ?? "" },
                set: { draft.thresholds[key]?[keyPath: path] = $0 })
    }

    // MARK: tab 2 — Range (§6)

    private var rangeTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From:")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    hourWheel(selection: $draft.startHour, identifier: "editor.startHour")
                    Text("To:")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    hourWheel(selection: $draft.endHour, identifier: "editor.endHour")
                }
            }
            Section {
                if draft.startHour == draft.endHour {
                    Text("Start and end be the same.")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                } else if draft.startHour > draft.endHour {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars")
                            .foregroundStyle(Theme.secondaryText)
                        Text("This is a night activity")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.primaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("editor.nightNote")
                }
                DidYouKnowBox(key: "nightRange",
                              body: "This activity is rated per night.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .listRowBackground(Color.clear)
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

    // MARK: tab 3 — Review (§7)

    private func reviewTab(_ buildResult: (activity: AuthoredActivity?, issues: [String])) -> some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ActivityIconView(identifier: draft.iconSymbol, size: 20)
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.accentOrange, in: Circle())
                    Text(draft.label.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                }
                ForEach(draft.metrics, id: \.self) { key in
                    summaryRow(key)
                }
                rangeLine
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
            Section {
            } footer: {
                Text("You can always change these later by pressing the card in the home screen.")
            }
            if !isNew, onDelete != nil {
                deleteSection
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func summaryRow(_ key: String) -> some View {
        let mode = ThresholdMode.current(for: key, in: draft)
        return HStack(spacing: 6) {
            ActivityIconView(identifier: catalog.iconSymbol(for: key), size: 14)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 20)
            Text(summaryText(key, mode: mode))
                .font(.system(size: 14))
                .foregroundStyle(Theme.primaryText)
        }
    }

    /// "Temp 15–32 °C · Must-have" / "Wind ≤ 25 km/h · Nice-to-have" /
    /// "Moon · Show only".
    private func summaryText(_ key: String, mode: ThresholdMode) -> String {
        var parts = catalog.shortName(for: key)
        if let threshold = draft.thresholds[key], !threshold.isFlag {
            let unit = catalog.descriptor(for: key)?.unit ?? ""
            let suffix = unit.isEmpty ? "" : " \(unit)"
            let min = threshold.minText.trimmingCharacters(in: .whitespaces)
            let max = threshold.maxText.trimmingCharacters(in: .whitespaces)
            switch (min.isEmpty, max.isEmpty) {
            case (false, false): parts += " \(min)–\(max)\(suffix)"
            case (false, true): parts += " ≥ \(min)\(suffix)"
            case (true, false): parts += " ≤ \(max)\(suffix)"
            case (true, true): break
            }
        }
        return "\(parts) · \(mode.label)"
    }

    @ViewBuilder
    private var rangeLine: some View {
        let wrapped = draft.startHour > draft.endHour
        HStack(spacing: 8) {
            Image(systemName: wrapped ? "moon.stars" : "clock")
                .foregroundStyle(Theme.secondaryText)
            Text("\(Self.hourText(draft.startHour)) – \(Self.hourText(draft.endHour))\(wrapped ? " night" : "")")
                .font(.system(size: 14))
                .foregroundStyle(Theme.primaryText)
        }
    }

    // MARK: delete (edit mode only)

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

    /// "12am", "1am" … "11pm" — the shared clock dialect (RangeText).
    static func hourText(_ hour: Int) -> String {
        RangeText.hourText(hour)
    }
}

// MARK: - tab header (§2)

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

#if DEBUG
#Preview("New (scratch)") {
    NavigationStack {
        ActivityEditorView(existing: .blank(),
                           isNew: true,
                           onSave: { _ in })
    }
}

#Preview("New (template)") {
    NavigationStack {
        ActivityEditorView(existing: SeedTemplates.running.copyFromTemplate(),
                           isNew: true,
                           onSave: { _ in })
    }
}

#Preview("Edit (existing)") {
    NavigationStack {
        ActivityEditorView(existing: SeedTemplates.cycling,
                           isNew: false,
                           onSave: { _ in },
                           onDelete: {})
    }
}
#endif
