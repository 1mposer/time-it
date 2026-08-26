import Foundation

/// Composes the one-time "your home runs on a different clock" alert body.
/// Compares wall clocks (GMT offsets at the given instant), not zone
/// identifiers — two zones sharing an offset show identical times and need
/// no warning. Device-location permission is never involved: the device's
/// own zone is always known.
enum TimezoneMismatch {

    /// The alert body, or nil when the zones share a wall clock at `date`.
    static func warning(homeName: String,
                        forecastZone: TimeZone,
                        deviceZone: TimeZone,
                        at date: Date) -> String? {
        let delta = forecastZone.secondsFromGMT(for: date) - deviceZone.secondsFromGMT(for: date)
        guard delta != 0 else { return nil }
        let direction = delta > 0 ? "ahead of" : "behind"
        return "\(homeName) is \(offsetText(seconds: abs(delta))) \(direction) your device. "
            + "Dashboard times, including the clock, follow \(homeName) time."
    }

    private static func offsetText(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append("\(minutes) minutes") }
        return parts.joined(separator: " ")
    }
}
