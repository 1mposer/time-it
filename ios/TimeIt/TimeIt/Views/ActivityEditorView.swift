import SwiftUI

/// The authoring surface (#5b §5): one Form used for both create (from the
/// add flow) and edit (from the card gear). Save stays disabled until the
/// draft is a valid ADR-0005 body — one invalid Activity would 400 the whole
/// dashboard (atomic validation), so an invalid one can never be saved.
struct ActivityEditorView: View {
    private let isNew: Bool
    private let catalog: MetricCatalogProviding
    private let onSave: (AuthoredActivity) -> Void
    private let onDelete: (() -> Void)?

    @State private var draft: ActivityDraft
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    /// Manifest activity icons (design-decisions §A) — derived from the
    /// Template catalog so a new Template's icon appears here without a
    /// second hand-maintained list; the draft's own icon is always included
    /// so editing an activity with an unlisted icon can't silently lose it.
    private var iconChoices: [String] {
        var choices = SeedTemplates.all.map(\.iconSymbol)
        choices.append("questionmark.circle")
        if !choices.contains(draft.iconSymbol) {
            choices.insert(draft.iconSymbol, at: 0)
        }
        return choices
    }

    init(existing: AuthoredActivity,
         isNew: Bool,
         catalog: MetricCatalogProviding = StaticMetricCatalog(),
         onSave: @escaping (AuthoredActivity) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.isNew = isNew
        self.catalog = catalog
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: ActivityDraft(from: existing))
    }

    var body: some View {
        // One parse+validate pass per render — the Form re-renders on every
        // keystroke, so computing this per consumer would triple the work.
        let buildResult = draft.result(against: catalog)
        Form {
            nameAndIconSection
            metricsSection
            if !selectedThresholdables.isEmpty {
                thresholdsSection
            }
            windowSection
            issuesSection(buildResult.issues)
            if !isNew, onDelete != nil {
                deleteSection
            }
        }
        .navigationTitle(isNew ? "New Activity" : "Edit Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("editor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let activity = draft.result(against: catalog).activity else { return }
                    onSave(activity)
                    dismiss()
                }
                .disabled(buildResult.activity == nil)
                .accessibilityIdentifier("editor.save")
            }
        }
    }

    // MARK: name & icon

    private var nameAndIconSection: some View {
        Section("Name & Icon") {
            TextField("Activity name", text: $draft.label)
                .accessibilityIdentifier("editor.name")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(iconChoices, id: \.self) { symbol in
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
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: metric picker (LIVE only — the catalog offers nothing else)

    private var metricsSection: some View {
        Section {
            ForEach(catalog.metrics) { descriptor in
                Button {
                    draft.toggleMetric(descriptor.key)
                } label: {
                    HStack(spacing: 10) {
                        ActivityIconView(identifier: descriptor.iconSymbol, size: 15)
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 22)
                        Text(descriptor.displayName)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        if draft.isSelected(descriptor.key) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.accentOrange)
                        }
                    }
                }
                .accessibilityIdentifier("metric.\(descriptor.key)")
            }
        } header: {
            Text("Metrics")
        } footer: {
            Text("Selected metrics appear on the card in this order. The first three show as chips.")
        }
    }

    // MARK: thresholds

    private var selectedThresholdables: [MetricDescriptor] {
        draft.metrics.compactMap { key in
            catalog.descriptor(for: key).flatMap { $0.isThresholdable ? $0 : nil }
        }
    }

    private var thresholdsSection: some View {
        Section {
            ForEach(selectedThresholdables) { descriptor in
                thresholdRows(for: descriptor)
            }
        } header: {
            Text("Thresholds")
        } footer: {
            Text("A metric without a threshold is shown on the card but doesn't affect the rating. Required thresholds make the hour Bad when they fail; optional ones make it Good instead of Perfect.")
        }
    }

    @ViewBuilder
    private func thresholdRows(for descriptor: MetricDescriptor) -> some View {
        if draft.thresholds[descriptor.key] != nil {
            let binding = thresholdBinding(for: descriptor.key)
            if descriptor.kind == .flag {
                Text("\(descriptor.displayName): fails the hour when active")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack {
                    Text("\(descriptor.displayName) min")
                    Spacer()
                    TextField(descriptor.unit.isEmpty ? "none" : descriptor.unit, text: binding.minText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .accessibilityIdentifier("editor.min.\(descriptor.key)")
                }
                HStack {
                    Text("\(descriptor.displayName) max")
                    Spacer()
                    TextField(descriptor.unit.isEmpty ? "none" : descriptor.unit, text: binding.maxText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .accessibilityIdentifier("editor.max.\(descriptor.key)")
                }
            }
            Toggle("\(descriptor.displayName) required", isOn: binding.required)
                .accessibilityIdentifier("editor.required.\(descriptor.key)")
            Button("Remove \(descriptor.displayName) threshold", role: .destructive) {
                draft.removeThreshold(for: descriptor.key)
            }
            .font(.system(size: 14))
            .accessibilityIdentifier("editor.removeThreshold.\(descriptor.key)")
        } else {
            Button("Add threshold for \(descriptor.displayName)") {
                draft.addThreshold(for: descriptor)
            }
            .accessibilityIdentifier("editor.addThreshold.\(descriptor.key)")
        }
    }

    /// Bindings into the draft's threshold for one metric. The rows above only
    /// render while the entry exists; the fallback covers the removal frame.
    private func thresholdBinding(for key: String) -> (minText: Binding<String>, maxText: Binding<String>, required: Binding<Bool>) {
        (minText: Binding(get: { draft.thresholds[key]?.minText ?? "" },
                          set: { draft.thresholds[key]?.minText = $0 }),
         maxText: Binding(get: { draft.thresholds[key]?.maxText ?? "" },
                          set: { draft.thresholds[key]?.maxText = $0 }),
         required: Binding(get: { draft.thresholds[key]?.required ?? true },
                           set: { draft.thresholds[key]?.required = $0 }))
    }

    // MARK: time window

    private var windowSection: some View {
        Section {
            Toggle("Only at certain hours", isOn: $draft.windowEnabled)
                .accessibilityIdentifier("editor.windowToggle")
            if draft.windowEnabled {
                Picker("From", selection: $draft.startHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Self.hourText(hour)).tag(hour)
                    }
                }
                .accessibilityIdentifier("editor.startHour")
                Picker("Until", selection: $draft.endHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Self.hourText(hour)).tag(hour)
                    }
                }
                .accessibilityIdentifier("editor.endHour")
                windowHint
            }
        } header: {
            Text("Time window")
        } footer: {
            Text("Hours are in the forecast location's local time. End before start wraps midnight — the activity is rated per night.")
        }
    }

    @ViewBuilder
    private var windowHint: some View {
        if draft.startHour == draft.endHour {
            Text("Start and end can't match — turn the window off for whole-day")
                .font(.system(size: 13))
                .foregroundStyle(.red)
        } else if draft.startHour > draft.endHour {
            Text("Overnight — wraps midnight (nocturnal)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        } else {
            Text("Same day")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: issues (why Save is disabled)

    @ViewBuilder
    private func issuesSection(_ issues: [String]) -> some View {
        if !issues.isEmpty {
            Section("Before you can save") {
                ForEach(issues, id: \.self) { issue in
                    Text(issue)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
            }
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

    /// "12am", "1am" … "11pm" — matches the timeline axis label style.
    static func hourText(_ hour: Int) -> String {
        switch hour {
        case 0: return "12am"
        case 1...11: return "\(hour)am"
        case 12: return "12pm"
        default: return "\(hour - 12)pm"
        }
    }
}
