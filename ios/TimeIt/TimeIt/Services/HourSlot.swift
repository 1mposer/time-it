import Foundation

/// One day-local hour as the card strip and the detail carousel draw it
/// (owner ruling 2026-11-04: "gone hours are drawn, grey, with no weather").
///
/// The forecast starts at the current hour, so a Range that began earlier
/// today has hours BEFORE `hours[0]`. Those hours are still drawn: their
/// `position` continues the global `hours[]` index space backwards (−1 is
/// the hour before `hours[0]`), and their `index` is nil — there is no
/// forecast data for them. A position past the horizon has no index either.
struct HourSlot: Equatable, Hashable {
    /// The slot's place in the global index space; may be negative or
    /// ≥ `hours.count`.
    let position: Int
    /// The 0–23 clock hour in the forecast location's zone.
    let localHour: Int
    /// The `hours[]` index carrying this hour's data; nil when there is none.
    let index: Int?
}

/// Row 1 under the detail pill row (owner rulings 2026-11-04): the user's
/// chosen Range in exactly ONE place on the detail, and it never changes —
/// "Your range 6 – 10am" wherever the carousel is, with " · Time passed" once
/// the WHOLE Range has ended (same line, no extra height). It never names
/// the carousel's span: away from the Range only `showsReturn` flips, so the
/// return button appears at the line's end (the span is named once, in the
/// hero's row 2). Reuses `RangeText.chipLabel`, so the am/pm rules are the
/// card chip's (and the server clock labels').
struct RangeLine: Equatable {
    let text: String
    let showsReturn: Bool

    /// `rangeHasPassed` (`TimeDeriver.rangeHasPassed`) words the Range; it
    /// holds on and away from it, so stepping away never changes the text.
    init(window: WindowSpec, isAtRange: Bool, rangeHasPassed: Bool = false) {
        let range = "Your range \(RangeText.chipLabel(window))"
        text = rangeHasPassed ? "\(range) · Time passed" : range
        showsReturn = !isAtRange
    }
}
