import Foundation

/// Settings strings the fresh-eyes pass ruled (spec §3, owner 2026-11-12).
/// Pure, so SettingsCopyTests pins them without a view.
enum SettingsCopy {
    /// Under the Notifications switch (row 2a): what arrives, and when.
    static let notificationsFooter =
        "A morning summary of your best hours, and an alert when a Perfect window opens."
}

/// Why the city picker opened. Nil (the dashboard CTA, "Set home location")
/// shows no reason line; the Notifications switch's detour does (row 2a).
enum CityPickerReason: Equatable {
    case notifications

    var headline: String {
        switch self {
        case .notifications: return "Pick a city so alerts know where to look."
        }
    }

    static func headline(for reason: CityPickerReason?) -> String? {
        reason?.headline
    }
}
