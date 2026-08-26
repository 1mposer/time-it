import Foundation

/// The client-side authored Activity — the editable superset of the wire
/// shape. Carries UI metadata plus the wire fields; projects to
/// `ActivityInput` at POST time. Codable so the list persists locally.
struct AuthoredActivity: Codable, Identifiable, Hashable {
    /// Client-authored, stable for the life of the Activity, unique within the
    /// POST body; echoed back as `activityId`. Never mutated on edit.
    let id: String
    var label: String
    /// SF Symbol name from the manifest; falls back to questionmark.circle.
    var iconSymbol: String
    /// The Template this was created from (nil for from-scratch). UI metadata only.
    var templateOrigin: String?
    /// Ordered render superset; every entry must be a LIVE metric key.
    var displayMetrics: [String]
    /// The evaluated subset — `thresholds.keys ⊆ displayMetrics`. May be empty
    /// (show-but-don't-judge is legal).
    var thresholds: [String: Threshold]
    /// nil = DORMANT — stored and visible, but excluded from every request
    /// and device snapshot. Wrap (startHour > endHour) = nocturnal.
    var window: WindowSpec?

    /// A wrapped window is the only nocturnal signal (ADR-0005 §5) — it
    /// drives the "Tonight"/"… night" day labels.
    var isNocturnal: Bool { window?.isWrapped == true }

    /// An Activity without a confirmed Range never rates and never pushes.
    var isDormant: Bool { window == nil }

    /// Projection to the wire: drops UI-only fields; includes `window` only
    /// when present.
    var activityInput: ActivityInput {
        ActivityInput(id: id,
                      label: label,
                      displayMetrics: displayMetrics,
                      thresholds: thresholds,
                      window: window)
    }

    /// A from-scratch starting point: fresh id, empty everything, guardrail icon.
    static func blank() -> AuthoredActivity {
        AuthoredActivity(id: UUID().uuidString,
                         label: "",
                         iconSymbol: "questionmark.circle",
                         templateOrigin: nil,
                         displayMetrics: [],
                         thresholds: [:],
                         window: nil)
    }

    /// A user-owned copy of this Template: fresh request-unique id, origin
    /// recorded, everything else carried over for the editor to tweak.
    func copyFromTemplate() -> AuthoredActivity {
        AuthoredActivity(id: UUID().uuidString,
                         label: label,
                         iconSymbol: iconSymbol,
                         templateOrigin: id,
                         displayMetrics: displayMetrics,
                         thresholds: thresholds,
                         window: window)
    }
}

// MARK: - Client-side validation (mirrors the server's ADR-0005 rules)

extension AuthoredActivity {

    var isValid: Bool { validationIssues.isEmpty }

    var validationIssues: [String] { validationIssues(against: StaticMetricCatalog()) }

    /// Mirrors the server's per-activity validation — one invalid Activity
    /// 400s the WHOLE request, so nothing failing these checks may be saved.
    /// The threshold-shape checks (flag vs numeric kind) exist ONLY here;
    /// the server does not catch that class yet (gap recorded for Issue #8).
    func validationIssues(against catalog: MetricCatalogProviding) -> [String] {
        var issues: [String] = []
        let liveKeys = catalog.liveKeys

        if id.isEmpty {
            issues.append("id must be a non-empty string")
        }
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Name can't be empty")
        }
        if displayMetrics.isEmpty {
            issues.append("Pick at least one metric to show")
        }
        for metric in displayMetrics where !liveKeys.contains(metric) {
            issues.append("\(metric) is not an available metric")
        }

        let displaySet = Set(displayMetrics)
        for (metric, threshold) in thresholds {
            if !liveKeys.contains(metric) {
                issues.append("\(metric) is not an available metric")
                continue
            }
            if !displaySet.contains(metric) {
                issues.append("\(metric) has a threshold but is not shown")
                continue
            }
            guard let descriptor = catalog.descriptor(for: metric) else { continue }
            if !descriptor.isThresholdable {
                issues.append("\(metric) can be shown but not thresholded")
                continue
            }
            if threshold.isFlag {
                if descriptor.kind != .flag {
                    issues.append("\(metric) takes min/max bounds, not an alert flag")
                    continue
                }
                if threshold.forbidTrue != true {
                    issues.append("\(metric): a flag threshold must forbid the alert")
                }
            } else {
                if descriptor.kind == .flag {
                    issues.append("\(metric) is an alert — it can only be thresholded as a flag")
                    continue
                }
                if threshold.min == nil && threshold.max == nil {
                    issues.append("\(metric) needs at least one of min/max")
                }
                if let min = threshold.min, min.isFinite == false {
                    issues.append("\(metric): min isn't a number")
                }
                if let max = threshold.max, max.isFinite == false {
                    issues.append("\(metric): max isn't a number")
                }
                if let min = threshold.min, let max = threshold.max, min > max {
                    issues.append("\(metric): min is greater than max")
                }
            }
        }

        if let window {
            let hours = 0...23
            if !hours.contains(window.startHour) || !hours.contains(window.endHour) {
                issues.append("Window hours must be between 0 and 23")
            } else if window.startHour == window.endHour {
                issues.append("Window start and end can't match")
            }
        }

        return issues
    }
}
