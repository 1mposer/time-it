import Foundation

/// The editor's working copy of one Activity: raw text fields and toggles
/// that build into an `AuthoredActivity` only when every validation rule
/// passes — Save stays disabled otherwise.
struct ActivityDraft: Equatable {
    let id: String
    let templateOrigin: String?
    var label: String
    var iconSymbol: String
    /// Ordered selection — becomes displayMetrics in selection order.
    var metrics: [String]
    var thresholds: [String: ThresholdDraft]
    var startHour: Int
    var endHour: Int
    /// Whether the incoming activity already carried a confirmed window —
    /// seeds the wizard's `rangeConfirmed` (an untouched prefill is not a
    /// confirmed Range; a previously saved one is).
    let hadWindow: Bool

    /// A live activity drafts at its own range; a dormant one at its
    /// template's prefill — a starting value, confirmed only by saving.
    init(from activity: AuthoredActivity) {
        id = activity.id
        templateOrigin = activity.templateOrigin
        label = activity.label
        iconSymbol = activity.iconSymbol
        metrics = activity.displayMetrics
        thresholds = activity.thresholds.mapValues(ThresholdDraft.init(from:))
        let prefill = activity.window ?? SeedTemplates.prefill(for: activity)
        startHour = prefill.startHour
        endHour = prefill.endHour
        hadWindow = activity.window != nil
    }

    // MARK: metric selection — a threshold can only exist for a selected metric

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

    /// §4's one-tap select: selects the metric AND pre-creates its preset
    /// Must-have threshold (display-only metrics just select). A no-op when
    /// already selected — re-tapping must not clobber authored values.
    mutating func selectWithPreset(_ descriptor: MetricDescriptor) {
        guard !isSelected(descriptor.key) else { return }
        metrics.append(descriptor.key)
        if descriptor.isThresholdable {
            thresholds[descriptor.key] = ThresholdDraft(preset: descriptor)
        }
    }

    mutating func removeThreshold(for key: String) {
        thresholds[key] = nil
    }

    // MARK: build

    /// Builds the Activity, or explains why it can't be saved yet. `activity`
    /// is non-nil exactly when `issues` is empty. A saved draft always
    /// carries its range — saving is what ends dormancy.
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
                                        window: WindowSpec(startHour: startHour, endHour: endHour))
        issues += activity.validationIssues(against: catalog)
        return (issues.isEmpty ? activity : nil, issues)
    }

    /// Empty text = no bound; non-numeric text is an issue, not a silent nil.
    /// Non-finite input ("inf"/"nan") is rejected — JSONEncoder would throw.
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
/// input never crashes; flags carry only the required toggle.
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

    /// The one-tap prefill: the metric's preset bounds as a Must-have
    /// threshold (`required: true`), zero typing needed.
    init(preset descriptor: MetricDescriptor) {
        minText = descriptor.presetMin.map(Self.format) ?? ""
        maxText = descriptor.presetMax.map(Self.format) ?? ""
        required = true
        isFlag = descriptor.kind == .flag
    }

    /// Int(Double) traps outside Int64's range, so only whole numbers safely
    /// inside it take the integer form. Internal — the threshold slider writes
    /// its snapped values back through the same formatting.
    static func format(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}
