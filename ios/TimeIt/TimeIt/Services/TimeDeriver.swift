import Foundation

/// The single place that turns `forecastStart` + `timezone` + an hours[] index
/// into wall-clock labels and local-day buckets — always in the FORECAST
/// LOCATION's zone, never the device zone (ADR-0004). Feeds the timeline axis,
/// the detail hour rows, and the card's day label.
struct TimeDeriver {
    private let start: Date
    private let calendar: Calendar
    private let hourFormatter: DateFormatter
    private let weekdayFormatter: DateFormatter

    init?(forecastStart: String, timezone: String) {
        guard let date = ISO8601DateFormatter().date(from: forecastStart),
              let zone = TimeZone(identifier: timezone) else {
            return nil
        }
        start = date

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        calendar = cal

        // en_US_POSIX pins the output shape ("4pm", "Sunday") independent of
        // the device locale, matching the guidelines' axis labels.
        hourFormatter = DateFormatter()
        hourFormatter.locale = Locale(identifier: "en_US_POSIX")
        hourFormatter.timeZone = zone
        hourFormatter.dateFormat = "ha"

        weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.timeZone = zone
        weekdayFormatter.dateFormat = "EEEE"
    }

    /// The UTC instant of `hours[index]`.
    func date(at index: Int) -> Date {
        start.addingTimeInterval(TimeInterval(index) * 3600)
    }

    /// Compact clock label in the location zone, e.g. "4pm", "12am".
    func hourLabel(at index: Int) -> String {
        hourFormatter.string(from: date(at: index)).lowercased()
    }

    /// Which local calendar day (0 = the day containing hours[0]) an index falls on.
    func dayOrdinal(at index: Int) -> Int {
        calendar.dateComponents([.day],
                                from: calendar.startOfDay(for: start),
                                to: calendar.startOfDay(for: date(at: index))).day ?? 0
    }

    /// "Today" / "Tomorrow" / weekday name, relative to the forecast's day 0
    /// in the location zone (dayIndex 0 is by definition "Today" there).
    func dayName(forDayIndex dayIndex: Int) -> String {
        switch dayIndex {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            guard let day = calendar.date(byAdding: .day, value: dayIndex, to: calendar.startOfDay(for: start)) else {
                return "Day \(dayIndex)"
            }
            return weekdayFormatter.string(from: day)
        }
    }

    /// The contiguous hours[] index range belonging to a local calendar day —
    /// the card timeline's real axis (never a hardcoded 6am–midnight span).
    /// Nil when the day is beyond the forecast horizon.
    func hourRange(forDayIndex dayIndex: Int, hourCount: Int) -> Range<Int>? {
        guard hourCount > 0 else { return nil }
        var lower: Int?
        for index in 0..<hourCount {
            let ordinal = dayOrdinal(at: index)
            if ordinal == dayIndex, lower == nil {
                lower = index
            }
            if ordinal > dayIndex, let lower {
                return lower..<index
            }
        }
        if let lower {
            return lower..<hourCount
        }
        return nil
    }
}
