import SwiftUI

/// A DORMANT Activity's card: a template preview, NOT a rated card — no
/// weather, no timeline, no chips. "Set your range →" opens the editor with
/// the Range prefill loaded (confirmation = saving; the only door out of
/// dormancy); "✕" dismisses (remembered in preferences, survives re-seeds).
struct ShowcaseCardView: View {
    let activity: AuthoredActivity
    var catalog: MetricCatalogProviding = StaticMetricCatalog()
    let onSetRange: () -> Void
    let onDismiss: () -> Void

    /// The TEMPLATE tag marks catalog descendants; a stray dormant authored
    /// Activity (dev installs) renders the same card without it.
    private var isTemplate: Bool {
        activity.templateOrigin != nil || SeedTemplates.all.contains { $0.id == activity.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                ActivityIconView(identifier: activity.iconSymbol, size: 18)
                    .foregroundStyle(Theme.primaryText.opacity(0.75))
                    .accessibilityHidden(true)
                Text(activity.label)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(Theme.primaryText)
                if isTemplate {
                    Text("TEMPLATE")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.timelineTrack, in: Capsule())
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss \(activity.label)")
                .accessibilityIdentifier("showcase.dismiss.\(activity.id)")
            }
            Text(metricSummary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            Button(action: onSetRange) {
                HStack(spacing: 5) {
                    Text("Set your range")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.accentInteractive)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("showcase.setRange.\(activity.id)")
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        // .contain creates a named CONTAINER — a bare identifier on the
        // stack would propagate onto every child and clobber the buttons'
        // own XCUI identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showcase.\(activity.id)")
    }

    /// e.g. "Temperature · Wind Speed · Rainfall · UV Index" — same one-line
    /// summary format as the Add sheet's template rows.
    private var metricSummary: String {
        activity.displayMetrics
            .map { catalog.displayName(for: $0) }
            .joined(separator: " · ")
    }
}

#if DEBUG
#Preview("Dormant templates") {
    ScrollView {
        VStack(spacing: 10) {
            ForEach(SeedTemplates.firstLaunchSeeds) { activity in
                ShowcaseCardView(activity: activity,
                                 onSetRange: {},
                                 onDismiss: {})
            }
        }
        .padding(14)
    }
    .background(Theme.appBackground)
}
#endif
