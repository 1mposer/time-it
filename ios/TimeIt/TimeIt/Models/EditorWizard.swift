import Foundation

/// The four wizard tabs of the Activity editor (§1 of the redesign) and
/// their completion rules. Green in the tab header = live validity: a tab is
/// complete the moment its rule passes and reverts if the user breaks it —
/// never "visited".
enum EditorStep: Int, CaseIterable {
    case nameIcon = 0
    case metrics
    case range
    case review

    /// The capsule-segment label in the tab header.
    var title: String {
        switch self {
        case .nameIcon: return "Name"
        case .metrics: return "Metrics"
        case .range: return "Range"
        case .review: return "Review"
        }
    }

    /// The tab's completion rule (the §1 table).
    func isComplete(draft: ActivityDraft, catalog: MetricCatalogProviding,
                    rangeConfirmed: Bool) -> Bool {
        switch self {
        case .nameIcon:
            return !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && draft.iconSymbol != "questionmark.circle"
        case .metrics:
            guard !draft.metrics.isEmpty else { return false }
            // "Every threshold parses" = no build issue attributable to a
            // thresholded metric. Threshold issues all lead with the metric
            // key ("temp: min isn't a number", "temp needs at least one of
            // min/max"); other tabs' issues never do.
            let issues = draft.result(against: catalog).issues
            return !issues.contains { issue in
                draft.thresholds.keys.contains { key in
                    issue.hasPrefix("\(key):") || issue.hasPrefix("\(key) ")
                }
            }
        case .range:
            return draft.startHour != draft.endHour && rangeConfirmed
        case .review:
            return draft.result(against: catalog).activity != nil
        }
    }

    /// Gating: tab *i* is tappable iff tabs `0..<i` are all complete.
    /// (Backward taps are always allowed — a lower rawValue is never gated.)
    func isUnlocked(draft: ActivityDraft, catalog: MetricCatalogProviding,
                    rangeConfirmed: Bool) -> Bool {
        EditorStep.allCases
            .filter { $0.rawValue < rawValue }
            .allSatisfy { $0.isComplete(draft: draft, catalog: catalog, rangeConfirmed: rangeConfirmed) }
    }
}

/// The 3-way threshold mode of a selected metric (§4): replaces the old
/// required-toggle and Add/Remove-threshold rows.
enum ThresholdMode: CaseIterable {
    /// Threshold with `required: true` — bad weather blocks the day.
    case mustHave
    /// Threshold with `required: false` — failing only downgrades Perfect to Good.
    case niceToHave
    /// No threshold — on the card, doesn't affect rating.
    case showOnly

    var label: String {
        switch self {
        case .mustHave: return "Must-have"
        case .niceToHave: return "Nice-to-have"
        case .showOnly: return "Show only"
        }
    }

    /// The mode the draft is currently in for one metric.
    static func current(for key: String, in draft: ActivityDraft) -> ThresholdMode {
        guard let threshold = draft.thresholds[key] else { return .showOnly }
        return threshold.required ? .mustHave : .niceToHave
    }

    /// Applies this mode to the draft. A mode flip never touches authored
    /// bound values; coming back from Show only re-creates the preset.
    func apply(for descriptor: MetricDescriptor, to draft: inout ActivityDraft) {
        switch self {
        case .mustHave, .niceToHave:
            if draft.thresholds[descriptor.key] == nil {
                draft.thresholds[descriptor.key] = ThresholdDraft(preset: descriptor)
            }
            draft.thresholds[descriptor.key]?.required = (self == .mustHave)
        case .showOnly:
            draft.removeThreshold(for: descriptor.key)
        }
    }
}
