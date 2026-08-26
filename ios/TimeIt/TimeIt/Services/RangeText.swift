import Foundation

/// Formats the authored Range itself (plain 0–23 hour ints, no timezone math
/// — a Range is already location-local): card chip, detail header, week axis.
/// `TimeDeriver` is the separate dialect for forecast-index clock times.
enum RangeText {

    /// "12am", "1am" … "11pm" — the axis-label clock style.
    static func hourText(_ hour: Int) -> String {
        switch hour {
        case 0: return "12am"
        case 1...11: return "\(hour)am"
        case 12: return "12pm"
        default: return "\(hour - 12)pm"
        }
    }

    /// The card's range chip: "6 – 10am" / "3 – 7pm" / "10pm – 4am" — same-
    /// meridiem collapse like `TimeDeriver.rangeLabel`, spaced dash.
    static func chipLabel(_ window: WindowSpec) -> String {
        let start = hourText(window.startHour)
        let end = hourText(window.endHour)
        guard start.suffix(2) == end.suffix(2) else { return "\(start) – \(end)" }
        return "\(start.dropLast(2)) – \(end)"
    }

    /// States the Range once for the detail header:
    /// "Your window: 6 – 10am daily" / "Your window: 10pm – 4am nightly".
    static func headerLabel(_ window: WindowSpec) -> String {
        "Your window: \(chipLabel(window)) \(window.isWrapped ? "nightly" : "daily")"
    }

    /// The week axis, rendered once: start / midpoint / end ("6am"/"8am"/"10am";
    /// nocturnal "10pm"/"1am"/"4am"). Midpoint floors on odd durations —
    /// Ranges are whole-hour.
    static func axisLabels(_ window: WindowSpec) -> [String] {
        let duration = (window.endHour - window.startHour + 24) % 24
        let midpoint = (window.startHour + duration / 2) % 24
        return [hourText(window.startHour), hourText(midpoint), hourText(window.endHour)]
    }
}
