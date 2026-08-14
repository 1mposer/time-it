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

    /// The 0–23 clock hour of `hours[index]` in the location zone — the client
    /// twin of the server's internal `localHour` tag (stripped from the wire).
    /// Drives the Range filter for the card slice and the detail's range hours.
    func localHour(at index: Int) -> Int {
        calendar.component(.hour, from: date(at: index))
    }

    /// Which local calendar day (0 = the day containing hours[0]) an index falls on.
    func dayOrdinal(at index: Int) -> Int {
        calendar.dateComponents([.day],
                                from: calendar.startOfDay(for: start),
                                to: calendar.startOfDay(for: date(at: index))).day ?? 0
    }

    /// "Today" / "Tomorrow" / weekday name, relative to the forecast's day 0
    /// in the location zone (dayIndex 0 is by definition "Today" there).
    ///
    /// For a nocturnal activity (wrapped window), `dayIndex` is the EVENING's
    /// ordinal (ADR-0004 amendment), so labels are night-phrased: "Tonight",
    /// "Tomorrow night", "<Weekday> night". The early-morning tail belongs to
    /// its evening, never the next day.
    func dayName(forDayIndex dayIndex: Int, nocturnal: Bool = false) -> String {
        switch dayIndex {
        case 0: return nocturnal ? "Tonight" : "Today"
        case 1: return nocturnal ? "Tomorrow night" : "Tomorrow"
        default:
            guard let day = calendar.date(byAdding: .day, value: dayIndex, to: calendar.startOfDay(for: start)) else {
                return "Day \(dayIndex)"
            }
            let weekday = weekdayFormatter.string(from: day)
            return nocturnal ? "\(weekday) night" : weekday
        }
    }

    /// "4–7pm" / "10pm–2am" — the best-stretch range label (spec 14 §2), the
    /// word-for-word twin of the server push copy's `rangeLabel`
    /// (`src/jobs/labels.js`): same meridiem → suffix once; crossing → both.
    /// `endIndex` is exclusive, so its label is the stretch's end boundary.
    /// Indices are not bounds-checked against the horizon — an out-of-range
    /// index extrapolates to its (still correct) clock time rather than trap.
    /// Shares the known half-hour-zone limitation with `hourLabel`.
    func rangeLabel(startIndex: Int, endIndex: Int) -> String {
        let start = hourLabel(at: startIndex)
        let end = hourLabel(at: endIndex)
        guard start.suffix(2) == end.suffix(2) else { return "\(start)–\(end)" }
        return "\(start.dropLast(2))–\(end)"
    }

    /// The card sublabel (spec 14 §2): "Today · 6–8pm" / "Tonight · 10pm–2am",
    /// matching push copy so a tapped push lands on its own receipt. With no
    /// stretch (a red day — server rating null) it is the plain day name:
    /// there is no window, the solid red slice carries the verdict.
    func sublabel(forDayIndex dayIndex: Int, startIndex: Int?, endIndex: Int?, nocturnal: Bool) -> String {
        let day = dayName(forDayIndex: dayIndex, nocturnal: nocturnal)
        guard let startIndex, let endIndex else { return day }
        return "\(day) · \(rangeLabel(startIndex: startIndex, endIndex: endIndex))"
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
