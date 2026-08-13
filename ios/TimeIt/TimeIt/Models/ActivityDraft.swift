import Foundation

/// The editor's working copy of one Activity (#5b §5): raw text fields and
/// toggles that build into an `AuthoredActivity` only when every ADR-0005 rule
/// passes — Save stays disabled otherwise (the atomic-400 guard, §7).
struct ActivityDraft: Equatable {
    let id: String
    let templateOrigin: String?
    var label: String
    var iconSymbol: String
    /// Ordered selection — becomes displayMetrics in selection order.
    var metrics: [String]
    var thresholds: [String: ThresholdDraft]
    var windowEnabled: Bool
    var startHour: Int
    var endHour: Int

    init(from activity: AuthoredActivity) {
        id = activity.id
        templateOrigin = activity.templateOrigin
        label = activity.label
        iconSymbol = activity.iconSymbol
        metrics = activity.displayMetrics
        thresholds = activity.thresholds.mapValues(ThresholdDraft.init(from:))
        windowEnabled = activity.window != nil
        // Spec 14 §6 prefill: a live activity drafts at its own range; a
        // dormant one at its template's owner-picked range (from-scratch
        // 6–10am when no template matches) — a starting value, confirmed
        // only by saving.
        let prefill = activity.window ?? SeedTemplates.prefill(for: activity)
        startHour = prefill.startHour
        endHour = prefill.endHour
    }

    // MARK: metric selection (structural subset invariant — a threshold can
    // only exist for a selected metric)

    func isSelected(_ key: String) -> Bool { metrics.contains(key) }

    mutating func toggleMetric(_ key: String) {
        if let index = metrics.firstIndex(of: key) {
            metrics.remove(at: index)
            thresholds[key] = nil
        } else {
            metrics.append(key)
        }
    }

    mutating func addThreshold(for descriptor: MetricDescriptor) {
        thresholds[descriptor.key] = ThresholdDraft(isFlag: descriptor.kind == .flag)
    }

    mutating func removeThreshold(for key: String) {
        thresholds[key] = nil
    }

    // MARK: build

    /// Builds the Activity, or explains why it can't be saved yet. `activity`
    /// is non-nil exactly when `issues` is empty.
    func result(against catalog: MetricCatalogProviding) -> (activity: AuthoredActivity?, issues: [String]) {
        var issues: [String] = []
        var parsed: [String: Threshold] = [:]

        for (key, draft) in thresholds {
            if draft.isFlag {
                parsed[key] = Threshold(required: draft.required, type: "flag", forbidTrue: true)
                continue
            }
            let min = Self.parseBound(draft.minText, metric: key, bound: "min", issues: &issues)
            let max = Self.parseBound(draft.maxText, metric: key, bound: "max", issues: &issues)
            parsed[key] = Threshold(min: min, max: max, required: draft.required)
        }

        let activity = AuthoredActivity(id: id,
                                        label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                                        iconSymbol: iconSymbol,
                                        templateOrigin: templateOrigin,
                                        displayMetrics: metrics,
                                        thresholds: parsed,
                                        window: windowEnabled ? WindowSpec(startHour: startHour, endHour: endHour) : nil)
        issues += activity.validationIssues(against: catalog)
        return (issues.isEmpty ? activity : nil, issues)
    }

    /// Empty text = no bound; non-numeric text is an issue, not a silent nil
    /// (a silently dropped bound could save a bound-less threshold → 400).
    /// Non-finite input ("inf"/"nan") parses via Double(_:) but would make
    /// JSONEncoder throw on both persist and POST — reject it here.
    private static func parseBound(_ text: String, metric: String, bound: String, issues: inout [String]) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
              value.isFinite else {
            issues.append("\(metric): \(bound) isn't a number")
            return nil
        }
        return value
    }
}

/// One threshold's editable state. Numeric bounds stay as text so partial
/// input never crashes; flags carry only the required toggle (forbidTrue is
/// implied — `requireTrue` is never offered, Issue #8).
struct ThresholdDraft: Equatable {
    var minText: String = ""
    var maxText: String = ""
    var required: Bool = true
    var isFlag: Bool = false

    init(isFlag: Bool = false) {
        self.isFlag = isFlag
    }

    init(from threshold: Threshold) {
        minText = threshold.min.map(Self.format) ?? ""
        maxText = threshold.max.map(Self.format) ?? ""
        required = threshold.required
        isFlag = threshold.isFlag
    }

    private static func format(_ value: Double) -> String {
        // Int(Double) traps outside Int64's range (and on non-finite values),
        // so only whole numbers safely inside it take the integer form.
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}
