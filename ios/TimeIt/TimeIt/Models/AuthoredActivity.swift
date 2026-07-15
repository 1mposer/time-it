import Foundation

/// The client-side authored Activity (#5b §2) — the editable superset of the
/// wire shape. Carries UI metadata (icon, template origin) plus the wire
/// fields; projects to `ActivityInput` at POST time. Codable so the list
/// persists locally (ActivityStore).
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
    /// nil = whole day; wrap (startHour > endHour) = nocturnal night-stitch.
    var window: WindowSpec?

    /// A wrapped window is the only nocturnal signal (ADR-0005 §5) — it drives
    /// the "Tonight"/"… night" day labels.
    var isNocturnal: Bool { window?.isWrapped == true }

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

// MARK: - Client-side ADR-0005 validation (the atomic-400 guard, #5b §7)

extension AuthoredActivity {

    var isValid: Bool { validationIssues.isEmpty }

    var validationIssues: [String] { validationIssues(against: StaticMetricCatalog()) }

    /// Mirrors the server's validateRatingRequest for a single Activity. One
    /// invalid Activity 400s the WHOLE request (validation is atomic), so
    /// nothing failing these checks may ever be saved, let alone POSTed.
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
            if catalog.descriptor(for: metric)?.isThresholdable == false {
                // Applies to flag-shaped thresholds too: the backend would
                // accept e.g. a flag on `moon` and it would trivially never
                // fail — the silent false-Perfect this mirror exists to block.
                issues.append("\(metric) can be shown but not thresholded")
                continue
            }
            if threshold.isFlag {
                if threshold.forbidTrue != true {
                    issues.append("\(metric): a flag threshold must forbid the alert")
                }
            } else {
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
                issues.append("Window start and end can't match — turn the window off for whole-day")
            }
        }

        return issues
    }
}
