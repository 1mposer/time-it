import Foundation

/// The Template catalog (#5b §4.1): curated `AuthoredActivity` starting points
/// the user can add from. No longer the app's fixed activity list — the
/// dashboard reads the user's mutable ActivityStore, which this catalog only
/// (a) seeds on first launch (`firstLaunchSeeds`) and (b) populates the
/// "Add from Template" list (`all`).
///
/// Hard constraint: every metric here must be LIVE (`src/weather/metricCatalog.js`) —
/// one coming-soon metric is an atomic 400 that blanks the whole dashboard.
/// Icons come from the SF Symbols manifest (design-decisions §A) — never invent
/// a name.
///
/// ⚠️ PROVISIONAL threshold values — the exact numbers are unpinned (STATUS.md
/// §4). Do not treat them as product decisions.
enum SeedTemplates {

    static let cycling = AuthoredActivity(
        id: "cycling",
        label: "Cycling",
        iconSymbol: "figure.outdoor.cycle",
        templateOrigin: nil,
        displayMetrics: ["temp", "windSpeed", "rainFall", "uV"],
        thresholds: [
            "temp": Threshold(min: 15, max: 32, required: true),
            "windSpeed": Threshold(max: 25, required: false),
            "rainFall": Threshold(max: 0.2, required: true),
            "uV": Threshold(max: 8, required: false),
        ],
        window: nil
    )

    static let fishingLite = AuthoredActivity(
        id: "fishing-lite",
        label: "Fishing Lite",
        iconSymbol: "figure.fishing",
        templateOrigin: nil,
        displayMetrics: ["temp", "windSpeed", "cloudCover"],
        thresholds: [
            "temp": Threshold(min: 12, max: 36, required: true),
            "windSpeed": Threshold(max: 25, required: true),
            "cloudCover": Threshold(max: 80, required: false),
        ],
        window: nil
    )

    /// Diurnal land activity (#5b §4.1 suggested addition).
    static let running = AuthoredActivity(
        id: "running",
        label: "Running",
        iconSymbol: "figure.run", // TODO: verify SF Symbol (manifest ⚠︎ — owner's SF Symbols app pass)
        templateOrigin: nil,
        displayMetrics: ["temp", "humidity", "uV", "windSpeed"],
        thresholds: [
            "temp": Threshold(min: 10, max: 33, required: true),
            "humidity": Threshold(max: 70, required: false),
            "uV": Threshold(max: 7, required: false),
        ],
        window: nil
    )

    /// Nocturnal activity — its wrapped window exercises the night-stitch
    /// path end-to-end (#5b §4.1). `moon` is display-only (no threshold).
    static let stargazing = AuthoredActivity(
        id: "stargazing",
        label: "Stargazing",
        iconSymbol: "moon.stars.fill",
        templateOrigin: nil,
        displayMetrics: ["cloudCover", "moon", "temp", "visibility"],
        thresholds: [
            "cloudCover": Threshold(max: 20, required: true),
            "temp": Threshold(min: 8, max: 35, required: false),
            "visibility": Threshold(min: 8, required: false),
        ],
        window: WindowSpec(startHour: 22, endHour: 4)
    )

    /// The "Add from Template" catalog, in display order.
    static let all: [AuthoredActivity] = [cycling, fishingLite, running, stargazing]

    /// What ActivityStore seeds on first launch — the two #5a Templates, so
    /// the first run matches the #5a dashboard exactly (#5b §3).
    static let firstLaunchSeeds: [AuthoredActivity] = [cycling, fishingLite]
}
