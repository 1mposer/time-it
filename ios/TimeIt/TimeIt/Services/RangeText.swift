import Foundation

/// Copy derived from the authored Range alone (pure 0–23 hour ints, zero
/// timezone math — the Range is already location-local by contract): the
/// card's range chip, the detail's window header, and the detail week's
/// range-zoomed axis. Clock times tied to forecast indices stay in
/// `TimeDeriver` — this is the dialect for the user's OWN hours.
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

    /// The card's range chip: "6 – 10am" / "3 – 7pm" / "10pm – 4am" —
    /// same-meridiem collapse like `TimeDeriver.rangeLabel`, spaced dash per
    /// the approved card frames.
    static func chipLabel(_ window: WindowSpec) -> String {
        let start = hourText(window.startHour)
        let end = hourText(window.endHour)
        guard start.suffix(2) == end.suffix(2) else { return "\(start) – \(end)" }
        return "\(start.dropLast(2)) – \(end)"
    }

    /// The detail header's single statement of the Range (§7.1):
    /// "Your window: 6 – 10am daily" / "Your window: 10pm – 4am nightly".
    static func headerLabel(_ window: WindowSpec) -> String {
        "Your window: \(chipLabel(window)) \(window.isWrapped ? "nightly" : "daily")"
    }

    /// The range-zoomed week axis (§7.3), rendered once under the stack:
    /// start / midpoint / end ("6am"/"8am"/"10am"; nocturnal "10pm"/"1am"/"4am").
    /// The midpoint floors on odd durations — Ranges are whole-hour.
    static func axisLabels(_ window: WindowSpec) -> [String] {
        let duration = (window.endHour - window.startHour + 24) % 24
        let midpoint = (window.startHour + duration / 2) % 24
        return [hourText(window.startHour), hourText(midpoint), hourText(window.endHour)]
    }
}
