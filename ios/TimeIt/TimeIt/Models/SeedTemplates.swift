import Foundation

/// The Template catalog: curated `AuthoredActivity` starting points that seed
/// the store on first launch (`firstLaunchSeeds`) and populate the "Add from
/// Template" list (`all`). Each template's `window` is its Range prefill —
/// preloaded by the editor, confirmed only by saving. Every metric here must
/// be LIVE, or one bad metric 400s the whole dashboard.
/// ⚠️ Threshold values are PROVISIONAL, not product decisions.
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
        window: WindowSpec(startHour: 6, endHour: 10)
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
        window: WindowSpec(startHour: 15, endHour: 19)
    )

    static let running = AuthoredActivity(
        id: "running",
        label: "Running",
        iconSymbol: "figure.run", // TODO: verify SF Symbol name
        templateOrigin: nil,
        displayMetrics: ["temp", "humidity", "uV", "windSpeed"],
        thresholds: [
            "temp": Threshold(min: 10, max: 33, required: true),
            "humidity": Threshold(max: 70, required: false),
            "uV": Threshold(max: 7, required: false),
        ],
        window: WindowSpec(startHour: 6, endHour: 9)
    )

    /// Nocturnal — its wrapped window exercises the night-stitch path;
    /// `moon` is display-only (no threshold).
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

    /// What ActivityStore seeds on first launch — the full catalog as showcase
    /// cards, landing DORMANT: nothing POSTs until a range is confirmed.
    static let firstLaunchSeeds: [AuthoredActivity] = all.map(dormant)

    /// The template minus its Range prefill — the store shape of a showcase card.
    private static func dormant(_ template: AuthoredActivity) -> AuthoredActivity {
        var copy = template
        copy.window = nil
        return copy
    }

    /// The Range the editor preloads for a window-less activity: its
    /// template's range when it descends from the catalog, else 6–10am.
    static func prefill(for activity: AuthoredActivity) -> WindowSpec {
        let templateId = activity.templateOrigin ?? activity.id
        return all.first { $0.id == templateId }?.window
            ?? WindowSpec(startHour: 6, endHour: 10)
    }
}
