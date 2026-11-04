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

/// The single line under the detail pill row (owner ruling 2026-11-04): on
/// the Range it reads "Your range 6 – 10am" — "Your range 6 – 10am · Time
/// passed" once the WHOLE Range has ended (owner ruling 2026-11-04, same
/// line, no extra height); away from it "Showing 7 – 11am" with a return
/// button at its end, whatever the Range's time. Both halves reuse
/// `RangeText.chipLabel`, so the am/pm rules are the card chip's (and the
/// server clock labels').
struct RangeLine: Equatable {
    let text: String
    let showsReturn: Bool

    /// `spanEndHour` is the span's EXCLUSIVE end, as a Range's `endHour` is.
    /// `rangeHasPassed` (`TimeDeriver.rangeHasPassed`) words the Range only.
    init(window: WindowSpec, isAtRange: Bool, spanStartHour: Int, spanEndHour: Int,
         rangeHasPassed: Bool = false) {
        if isAtRange {
            let range = "Your range \(RangeText.chipLabel(window))"
            text = rangeHasPassed ? "\(range) · Time passed" : range
            showsReturn = false
        } else {
            let span = WindowSpec(startHour: spanStartHour, endHour: spanEndHour)
            text = "Showing \(RangeText.chipLabel(span))"
            showsReturn = true
        }
    }
}
