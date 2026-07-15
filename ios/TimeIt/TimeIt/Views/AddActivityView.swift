import SwiftUI

/// Presented from the ghost add-card (#5b §5). Two paths into the editor:
/// a Template copy (pre-filled, fresh id, origin recorded) or from scratch.
struct AddActivityView: View {
    @ObservedObject private var store: ActivityStore
    @State private var editorSeed: AuthoredActivity?
    @State private var showingCapAlert = false
    @Environment(\.dismiss) private var dismiss

    private let catalog: MetricCatalogProviding

    init(store: ActivityStore, catalog: MetricCatalogProviding = StaticMetricCatalog()) {
        _store = ObservedObject(wrappedValue: store)
        self.catalog = catalog
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Start from a Template") {
                    ForEach(SeedTemplates.all) { template in
                        Button {
                            editorSeed = template.copyFromTemplate()
                        } label: {
                            templateRow(template)
                        }
                        .accessibilityIdentifier("template.\(template.id)")
                    }
                }
                Section {
                    Button {
                        editorSeed = AuthoredActivity.blank()
                    } label: {
                        Label("Start from scratch", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addFromScratch")
                }
            }
            .navigationTitle("Add Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $editorSeed) { seed in
                ActivityEditorView(existing: seed,
                                   isNew: true,
                                   catalog: catalog,
                                   onSave: { activity in
                                       // add() can refuse: the cap may have been
                                       // reached since this sheet opened (another
                                       // scene sharing the store). Dismissing on a
                                       // refused add would fake a successful save.
                                       if store.add(activity) {
                                           dismiss() // closes the whole Add sheet
                                       } else {
                                           showingCapAlert = true
                                       }
                                   })
            }
            .alert("Activity limit reached", isPresented: $showingCapAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can keep up to \(ActivityStore.softCap) activities. Delete one to add another.")
            }
        }
    }

    private func templateRow(_ template: AuthoredActivity) -> some View {
        HStack(spacing: 12) {
            ActivityIconView(identifier: template.iconSymbol, size: 18)
                .foregroundStyle(Theme.primaryText.opacity(0.75))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Text(metricSummary(for: template))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// One-line metric summary, e.g. "Temperature · Wind Speed · Cloud Cover".
    private func metricSummary(for template: AuthoredActivity) -> String {
        template.displayMetrics
            .map { catalog.descriptor(for: $0)?.displayName ?? $0 }
            .joined(separator: " · ")
    }
}
