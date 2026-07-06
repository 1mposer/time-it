import Foundation

/// The two client-authored seed Templates POSTed on every load (grill Q8:
/// land + water, free metrics only, so nothing shows a lock on first launch).
///
/// Hard constraint: every metric here must be LIVE (`src/weather/metricCatalog.js`) —
/// one coming-soon metric is an atomic 400 that blanks the whole dashboard.
///
/// ⚠️ PROVISIONAL threshold values — the exact numbers are unpinned and will be
/// finalised in #5b (STATUS.md §4). Do not treat them as product decisions.
enum SeedTemplates {

    static let cycling = ActivityInput(
        id: "cycling",
        label: "Cycling",
        displayMetrics: ["temp", "windSpeed", "rainFall", "uV"],
        thresholds: [
            "temp": Threshold(min: 15, max: 32, required: true),
            "windSpeed": Threshold(max: 25, required: false),
            "rainFall": Threshold(max: 0.2, required: true),
            "uV": Threshold(max: 8, required: false),
        ]
    )

    static let fishingLite = ActivityInput(
        id: "fishing-lite",
        label: "Fishing Lite",
        displayMetrics: ["temp", "windSpeed", "cloudCover"],
        thresholds: [
            "temp": Threshold(min: 12, max: 36, required: true),
            "windSpeed": Threshold(max: 25, required: true),
            "cloudCover": Threshold(max: 80, required: false),
        ]
    )

    static let all: [ActivityInput] = [cycling, fishingLite]
}
