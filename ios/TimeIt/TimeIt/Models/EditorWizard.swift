import Foundation

// MARK: - EditorStep — wizard steps, completion & gating

/// The five steps of the Activity editor (owner rulings 2026-11-11, Lane A
/// item 4): Name → Metrics → Priority → Range → Review, walked with Back /
/// Next under a progress bar (the tab strip is gone). A step is complete the
/// moment its rule passes and reverts if the user breaks it — never
/// "visited".
enum EditorStep: Int, CaseIterable {
    case nameIcon = 0
    case metrics
    case priority
    case range
    case review

    /// The step's large heading (Figma `A/R2/Final`, 28pt Semibold). Review
    /// has none — its reveal carries its own title. Never the words "range"
    /// or "threshold" on screen (owner ruling 2026-08-22).
    var heading: String? {
        switch self {
        case .nameIcon: return "Name your activity"
        case .metrics: return "Pick what to watch"
        case .priority: return "What matters most?"
        case .range: return "When do you go?"
        case .review: return nil
        }
    }

    // MARK: Completion

    /// The step's completion rule.
    func isComplete(draft: ActivityDraft, catalog: MetricCatalogProviding,
                    rangeConfirmed: Bool) -> Bool {
        switch self {
        case .nameIcon:
            return !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && draft.iconSymbol != "questionmark.circle"
        case .metrics:
            guard MetricsGate.isMet(draft: draft) else { return false }
            // "Every threshold parses" = no build issue attributable to a
            // thresholded metric. Threshold issues all lead with the metric
            // key ("temp: min isn't a number", "temp needs at least one of
            // min/max"); other steps' issues never do.
            let issues = draft.result(against: catalog).issues
            return !issues.contains { issue in
                draft.thresholds.keys.contains { key in
                    issue.hasPrefix("\(key):") || issue.hasPrefix("\(key) ")
                }
            }
        case .priority:
            return PriorityChoice.gateIsMet(draft: draft)
        case .range:
            return draft.startHour != draft.endHour && rangeConfirmed
        case .review:
            return draft.result(against: catalog).activity != nil
        }
    }

    // MARK: Gating

    /// Step *i* is reachable iff steps `0..<i` are all complete. Backward
    /// moves are always allowed.
    func isUnlocked(draft: ActivityDraft, catalog: MetricCatalogProviding,
                    rangeConfirmed: Bool) -> Bool {
        EditorStep.allCases
            .filter { $0.rawValue < rawValue }
            .allSatisfy { $0.isComplete(draft: draft, catalog: catalog, rangeConfirmed: rangeConfirmed) }
    }

    // MARK: Landing

    /// The step the editor opens on when a caller asks for `requested` (the
    /// detail screen's Edit range / Edit metrics doors — #25). A saved
    /// Activity unlocks every step, so the request is honoured; a draft that
    /// does not lands on the highest unlocked step at or below the request,
    /// never on a locked one. Step 0 is always unlocked.
    static func landingStep(requested: EditorStep, draft: ActivityDraft,
                            catalog: MetricCatalogProviding, rangeConfirmed: Bool) -> EditorStep {
        EditorStep.allCases
            .filter { $0.rawValue <= requested.rawValue }
            .last { $0.isUnlocked(draft: draft, catalog: catalog, rangeConfirmed: rangeConfirmed) }
            ?? .nameIcon
    }
}

// MARK: - NameIconGate — the Name step's hint

/// The Name step's gate line (fresh-eyes row 10a, owner 2026-11-12): once a
/// name is typed and no icon is picked, Next is off and says why. The icon
/// stays required, no matter what — this is copy, never a relaxed gate.
enum NameIconGate {
    static let hint = "Pick an icon too."

    static func hint(draft: ActivityDraft) -> String? {
        let named = !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return named && draft.iconSymbol == "questionmark.circle" ? hint : nil
    }
}

// MARK: - MetricsGate — the two-metric minimum

/// The Metrics step's floor (owner ruling 2026-11-11, build 10): Next stays
/// off until at least two metrics are picked, on a new Activity and an
/// edited one alike — no grandfathering (the build-10 purge removed every
/// older single-metric Activity).
enum MetricsGate {
    static let minimum = 2

    static func isMet(draft: ActivityDraft) -> Bool {
        draft.metrics.count >= minimum
    }

    /// The gate's line under the grid.
    static let hint = "Pick at least two"
}

// MARK: - WizardProgress — the progress bar's fill

/// The progress bar never starts at zero (owner ruling 2026-11-11): Name
/// shows 0.12, then evenly to a full bar on Review.
enum WizardProgress {
    static let start: Double = 0.12

    static func fraction(for step: EditorStep) -> Double {
        let last = Double(EditorStep.allCases.count - 1)
        return start + (1 - start) * Double(step.rawValue) / last
    }
}

// MARK: - PriorityChoice — the Priority step over the threshold contract

/// The Priority step (owner ruling 2026-11-11, replacing the Priority / Show
/// only checkboxes): every metric picked on the Metrics step that can be
/// judged carries a threshold; pressing it here makes that threshold
/// `required: true` (it can turn a day Bad), leaving it unpressed keeps
/// `required: false` (it still shows, and can only turn Perfect into Good).
/// Display-only metrics (Moon Phase) never appear here.
enum PriorityChoice {

    /// The Priority grid's metrics: the picked, judged metrics in pick order.
    static func candidates(in draft: ActivityDraft) -> [String] {
        draft.metrics.filter { draft.thresholds[$0] != nil }
    }

    static func isChosen(_ key: String, in draft: ActivityDraft) -> Bool {
        draft.thresholds[key]?.required == true
    }

    /// Flips one metric between prioritised and not. A no-op for a metric
    /// with no threshold — bounds are never touched.
    static func toggle(_ key: String, in draft: inout ActivityDraft) {
        guard draft.thresholds[key] != nil else { return }
        draft.thresholds[key]?.required.toggle()
    }

    /// Next stays off until at least one metric is pressed (owner ruling 2a,
    /// "Press at least one."): with no required threshold no hour can ever be
    /// Bad, so the card could never turn red. A draft with nothing to judge
    /// (Moon Phase alone) has nothing to press and passes.
    static func gateIsMet(draft: ActivityDraft) -> Bool {
        let keys = candidates(in: draft)
        return keys.isEmpty || keys.contains { isChosen($0, in: draft) }
    }

    /// The gate's line under the grid.
    static let gateHint = "Press at least one."
    /// The explainer under the heading (owner ruling 3b — as drawn).
    static let explainer = "Pressed ones matter most. The rest still show."
}
